# IPv4/IPv6 infrastructure and integrated release validation

## Authority and identity

This is the current operational companion to [IPV6.md](IPV6.md). The previous
seven-step IPv6 activation proposal is superseded: relay opt-in, client `/dns/`
defaults and infrastructure activation already exist. Do not reapply historical
repair/deployment scripts as desired-state owners.

The September 14, 2026 review began with a clean `main` at
`8e6a569b4b1805249638ceea31c7995ef707b50f`. The explicit change comparison is
`ad3529a041528c07dd6714a98c0f70fefeb2366b`, verified as an ancestor, also the
then-local `origin/main`. Four later commits are preserved. That comparison
is **not** a verified previous published revision. Current application version
in source is `1.0.1+119`; database schema 119 is a separate identity.

The initial review authorized repository edits, local builds, isolated tests
and read-only operational inspection. The user subsequently authorized the
local signed candidate (build 120, with no store-availability claim), source
commit/push/merge, and then relay redeployment. PR #3 merged as
`74ecbafeec31cf92c5efd1137f9feac85b2a855b`; that exact clean source was deployed
on September 14 as recorded below. DNS, firewall, credentials, nginx, coturn and
app distribution were not changed by this deployment.

The native TURN/TLS follow-up began on clean `main` at reviewed base
`74ecbafeec31cf92c5efd1137f9feac85b2a855b`, with no later commits or existing
edits. During that work, the documentation-only relay-deployment commits
`5c5c6d2dd` and `fcaf1d6ab` arrived and were preserved. The comparison base remains
`74ecbafe`; the current follow-up checkout is `main` at
`fcaf1d6abcf8c4b90e384034eea5201561b158e9` with the repair as local edits.
Production inspection in this follow-up is read-only. Its private
evidence is in `.codex-test-logs/native-turn-tls-20260914/`.

Private/raw run evidence is retained in ignored
`.codex-test-logs/dual-stack-priority4/`. `initial-identity.json` records the clean
checkout, comparison, original artifact hashes and timestamps;
`prior-artifact-preservation.json` checks retained copies before build outputs
are replaced. Artifact presence or a version number is not distribution proof.

## Active configuration owners and current observations

Observations began September 13 at 22:54 UTC (September 14 Berlin). The relay
process row includes the subsequent authorized September 14 deployment.
These are dated observations, not continuous monitoring; source identity is
established by the deployment receipt and running executable digest.

| Boundary | Observation and owner | What it establishes |
| --- | --- | --- |
| DNS | `mknoun.xyz` A `13.60.15.36`, TTL 3600; AAAA `2a05:d016:c4d:7100:ec85:94ed:b90d:e20`, TTL 600 | Configured DNS only |
| Relay process | `/etc/systemd/system/relay-server.service`; `/usr/local/bin/relay-server`; active since September 14 11:34:32 UTC | Source `74ecbafeec31cf92c5efd1137f9feac85b2a855b`, running executable SHA-256 `7e8927194308e91f9bab78098cbe2ff9d7db1839341daa7ef02b9fc6c036aa2b`; version label remains v1.10.7 |
| Relay environment | Base `/etc/mknoon/relay-server.env`; IPv6 drop-in `/etc/systemd/system/relay-server.service.d/60-ipv6.conf` loads `/etc/mknoon/relay-ipv6.env`; existing `app-diagnostics.conf` drop-in preserved | Runtime `RELAY_SERVER_IP6` equals AAAA and DNS IPv6 opt-in is true; backend Redis; all active configuration hashes unchanged by redeployment |
| Relay sockets | IPv4 plus exact configured IPv6: TCP/WS 4000, raw TCP 4005, UDP/QUIC 4002 | Bound listeners, independent of cloud ingress |
| nginx | `/etc/nginx/sites-enabled/mknoun.xyz`; certificate under `/etc/letsencrypt/live/mknoun.xyz/`; configuration test passed | IPv4/IPv6 WSS 4001 proxies to `http://127.0.0.1:4000`; HTTPS 443 also listens; that does not make 443 a TURN endpoint |
| coturn | `/usr/lib/systemd/system/coturn.service`, `/etc/turnserver.conf`; TLS files under `/etc/coturn/tls/` | IPv4 and IPv6 UDP/TCP 3478, TLS 5349; allocation range 49152–50175 |
| TURN address mapping | IPv4 `external-ip=13.60.15.36/172.31.34.24`; IPv6 has its own `relay-ip` | IPv4 mapping does not replace IPv6 allocation configuration |
| TURN credentials | Runtime advertises `turn:mknoun.xyz:3478?transport=udp`, `turn:mknoun.xyz:3478?transport=tcp`, `turns:mknoun.xyz:5349?transport=tcp` | Issuer configuration; allocation/media tested independently |
| APNs provider | Default environment `production`, topic `com.mknoon.app.voip`; routing remains per registered token environment | A service default does not establish a development token or signed app environment |
| Cloud ingress | Read-only AWS instance/security-group inspection in `eu-north-1` matches both public addresses | Both families admit TCP 4001/4005, UDP 4002, UDP/TCP 3478, TCP 5349 and UDP 49152–50175; ICMPv6 is allowed |
| Cloud routing and NACL | Associated subnet ACL and effective VPC route table were read through existing authorized AWS access | IPv4/IPv6 ingress and egress NACL permits, active default routes to the Internet Gateway, and security-group egress for both families |

Read-only source/configuration hashes and allowlisted directives are in
`remote-config.json`; actual sockets are in `remote-listeners-keyed.log`.
The earlier `ec2-user`/default-key SSH attempt failed; the repository's existing
key and `ubuntu` account succeeded with strict existing host-key verification.
No secret values were copied into these receipts. The historical
`docker-ws/fix_coturn_dual_stack_tls.py`, `fix_coturn_hairpin_peer.sh` and
`deploy_relay_v1100.sh` explain earlier changes but are not canonical deployment
owners. The general credential contract remains in
[turn-operations.md](../go-relay-server/docs/turn-operations.md).

The exact private relay IPv4 is the coturn hairpin exception. Keep the existing
loopback, private, link-local/metadata and multicast exclusions; do not expand
that exception to an entire private range. WS 4000 binds wildcards in the relay
but also retains legacy public IPv4 security-group admission on TCP 4000; it is
not loopback-only. No matching public IPv6 rule exists for raw WS 4000. Do not
automatically mirror legacy/admin allowances to IPv6 or remove working IPv4
without checking its consumers. Host UFW is inactive and the inspected nftables
ruleset is empty. The private `aws-*.private.json` receipts and redacted cloud
summary preserve the independent cloud configuration evidence. Configuration
admits the configured allocation range; the media probes sample allocations,
not every port in that range.

## Evidence matrix

The public probes use fresh disposable libp2p identities with no registered push
tokens. They authenticate the expected peer
`12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` and pin one endpoint/family.
The initial probes exercised reservations, empty mailbox reads and TURN
credentials. The deployment follow-up additionally exchanged synthetic message
and call-control bytes through production handlers, retrieved and acknowledged
them, tested legacy-reader quiet retention, and unregistered its rendezvous and
wake authority. These isolated generated identities are not user accounts;
opaque byte exchange is not phone display, audible media or APNs proof.

| Scenario or endpoint | Evidence | Remaining boundary |
| --- | --- | --- |
| Public IPv4 TCP 4005, WSS 4001, QUIC 4002 | After redeployment, authenticated reservations, signed rendezvous, ordinary/quiet custody bytes, legacy-reader retention, call-control exchange, ACK cleanup and fresh credentials pass in both mixed-family directions; `deploy-20260914T1123Z-74ecbafe/public-application-matrix.jsonl` | Signed-client content/media |
| Public IPv6 TCP 4005, WSS 4001, QUIC 4002 | Same deployment checks pass with actual IPv6 connections and normal WSS certificate validation | Native IPv6-only access-network and signed-client content/media |
| IPv4-only relay compatibility | Current tagged Go fixture passed with preserved `/dns/` client defaults | Whole-device IPv4-only network journey |
| Healthy dual-stack and mixed-family peers | Production-handler socket fixture passes IPv4/IPv4, IPv6/IPv6 and both mixed directions on TCP/WS/QUIC | Signed peers and native WebRTC media on the requested networks |
| Broken IPv6 with working IPv4 | Current native socket fault run passed failed handshakes and established chat/inbox path retirement | Network-wide outage and exact signed candidate |
| Blocked UDP | Current socket-scoped UDP blackhole tests preserve TCP/WSS messages; native TCP media separately passed | No claim of a device-wide UDP firewall or 443-only network |
| Established-session transition | Current Go fixtures observe successful IPv6 before fault and IPv4 on a later operation, preserving quiet custody | Established IPv6 **media** loss is not proved by messaging or by an always-IPv4 selected pair |
| Native IPv6-only access network | No authorized isolated network established for this run | Unverified, distinct from IPv6 loopback/public sockets on a dual-stack Mac |
| DNS64/NAT64 | No authorized isolated DNS64/NAT64 network established | Unverified; do not substitute AAAA, `/dns/`, or direct IPv6 success |
| TURN control/allocation matrix | `turn-matrix.json` records UDP/TCP/TLS, independently requested connection/allocation families, permissions, exact returned bytes and Refresh(0) cleanup | Initial IPv4 UDP failures remain. Longer fresh diagnostics returned 10/11 payloads before timeout for IPv4 allocation and 100/100 for IPv6 allocation, with cleanup. The narrow server capture saw ten ChannelData frames each way in the failed case; upstream loss versus NAT remapping remains unresolved. IPv6 UDP and all TCP/TLS initial cases returned 100 exact payloads each; host success is not native TLS/RTP/audio proof |
| TURN after relay redeployment | `deploy-20260914T1123Z-74ecbafe/turn-matrix.json`: fresh validated credentials, UDP/TCP/TLS with IPv4 control/IPv4 allocation and IPv6 control/IPv6 allocation all pass; 100 exact bidirectional payloads per case, permission/channel creation, authenticated responses and all 12 allocations released | Host sockets bound to Wi-Fi; TLS uses normal hostname/CA validation. This six-case smoke does not rerun cross-family allocations or supersede retained intermittent UDP failures, native TLS failure, signed-device or audible-media requirements |
| Current Android native UDP and TCP | Each transport passed all eight policy/direction cases and their restarts on Pixel/emulator: 32 endpoint receipts, DTLS and advancing bidirectional RTP, 16 fresh credential requests | Disposable debug fixture with isolated USB signaling broker; TURN media was not USB-forwarded. No production signaling, audible quality, signed-device or network-wide route-isolation claim |
| Android native TLS before/after | `.09` again failed `all-relayOnly-0` with no selected pair despite zero-exit drivers. The Android-only `.14` repair passes TLS-only protected media and the complete mixed-policy matrix against unchanged public coturn | Source/debug fixture, with native TLS and advancing RTP; signed distribution, audible sound and iOS parity remain separate. See the native repair evidence below |
| Full application call on isolated IPv4 fixtures | Existing production-call adapter/SIMS passed 27 assertions on the Pixel/emulator pair: fresh accounts/contacts, local production relay and coturn, semantic Start/native Answer, both call surfaces, per-endpoint RTP, known-Opus oracle, controls and cleanup | Separate source/debug artifact. The host oracle proves exact synthetic audio bytes; phone RTP and UI do not establish human-audible quality, signed distribution behavior or background APNs |
| Port-443-only calling | No advertised TURN 443 path; existing WSS control is 4001 | Documented limitation. Both control and media must be provisioned and independently tested before claiming support |
| Background call after six-minute idle | September 12–13 sandbox failures/passes remain dated evidence | A new signed-candidate trial must prove suspension, provider acceptance, PushKit, CallKit, adoption and media |
| Native encrypted database | Three existing integration tests pass on each of Android and iOS; iOS verifies the Android-exported encrypted snapshot's checksum, cipher parameters, schema and retained rows in disposable apps | Synthetic fixtures do not establish upgrade from the unknown previous published binary or signed-candidate compatibility |

The host's current IPv4 and IPv6 route/interface discovery shows Wi-Fi `en0`.
TURN probe sockets explicitly bind `en0`, verify the connected family and request
allocation family separately. No cellular, VPN, USB forwarding or alternate
address can satisfy those TURN probe cases. Socket-scoped local fault tests
remain explicitly local; they are not network-wide isolation evidence.

Available devices were discovered using Flutter, ADB and simctl: a USB Pixel 6
(API 37), three USB iPhones, and iOS simulators including a booted iPhone 17 Pro.
The existing Codex API 35 Android emulator was started without wiping data or
saving a snapshot, used for the two-peer checks, then stopped. Exact target IDs
are pinned in the private command/report receipts. Non-iOS-specific two-peer tests use the
USB Android plus an available Android emulator, with both IDs pinned and setup
through the existing automated harness. A model/OS-specific leg absent from the
live inventory is **N/A (target unavailable by project policy)**. Missing network
scenarios or required artifact evidence remain **unverified**, not N/A or PASS.

## Remaining network scenarios: current verification boundary

The follow-up comparison is `74ecbafeec31cf92c5efd1137f9feac85b2a855b`,
verified as an ancestor of the intended `main` checkout
`fcaf1d6abcf8c4b90e384034eea5201561b158e9`. Existing Android M144 `.14`,
native TLS proof, renewal-hook and documentation edits were preserved. The
concurrent signed-Android packaging documentation above was also preserved;
this follow-up tests separate debug APKs. Initial edits/configuration hashes,
the original diff, resolved Go modules, binding stamp, target/OS observations
and artifact receipts are in `.codex-test-logs/network-gaps-20260914/`.
Flutter is 3.47.2, Go is 1.25.0, `flutter_webrtc` is 1.6.0 and Android WebRTC
is 144.7559.14. This work changes diagnostic tests and adds a narrow operator
repair mode; it does not change application/relay runtime code, dependency pins,
certificates or deployed configuration.

The read-only relay audit ending at **13:30:58 UTC on September 14** supersedes
the earlier address-availability observation for that instant: `ens5` had only
its IPv4 and link-local IPv6 addresses. The configured global IPv6 address was
absent from **all** interfaces, while coturn still displayed sockets bound to
that address. `systemd-networkd` recorded a route-setting timeout at 13:03:00
and `ens5: Failed` at 13:03:04. Public IPv6 TCP probes and TURN allocation timed
out. These observations establish an unavailable endpoint prerequisite, not the
cause of the older IPv4 UDP loss. Fresh credential operations also intermittently
returned the helper's coarse `REQUEST_REJECTED`, including with an explicitly
pinned authenticated IPv4 relay address. Their underlying cause is unresolved.
Later SSH timed out before a final fixture directory/namespace could be created.
No production network repair, service restart or firewall change was performed.

**Prerequisite recovery, September 14 at 19:11 UTC:** after the operator
reported recovery, the hostname's IPv4 address differed from the earlier
numeric test pin. Requests through that old pin still failed. At the current
DNS address, SSH verified against the previous host key and the assigned global
IPv6 address matched DNS. Host TCP connections to relay port 4005 and TURN port
3478 passed over both IPv4 and IPv6. The existing production-default hostname
credential helper returned two valid, fresh bundles from two disposable clients;
its SHA-256 is
`9b314ffb8f3b9b3d58dbf1c0799a2f5596b61e4cc34e52bef007e4eb965e803f`.
No credential values were retained. Current observations supersede the earlier
service-availability blocker; future numeric fixture pins must be rediscovered.
They do not explain the original missing UDP packet or prove why the earlier
credential requests failed. Native media and complete access-network trials
were not rerun in this readiness check, and isolated device-facing IPv6-only
and DNS64/NAT64 networks remain separate prerequisites. Evidence is in
`.codex-test-logs/network-gaps-20260914/recovery-check-20260914T190715Z/`;
`summary.json` SHA-256 is
`b6118ba4ee0c80c2a3e615dd971c79e7bbdabae206f41edd4decf15606b80920`.
The table includes the later focused IPv4 UDP trials below. The other three
network scenarios remain unverified; the relay is no longer unavailable.

| Scenario | Exact topology attempted | Observed control/media families | Result | Cause/fix | Tests and evidence | Remaining limitation |
| --- | --- | --- | --- | --- | --- | --- |
| Established IPv6 audio loss with an alternative | USB Pixel 6/API 37 plus owned Codex API 35 emulator; local coturn and public TURN | Local native selected candidates IPv4; later public UDP proof observes emulator-to-TURN IPv4 media, phone connection family unobserved | **BLOCKED** | No established IPv6 media leg was demonstrated; no recovery-owner change justified | Earlier native receipts and focused `native-capture-corrected/native-public-udp4/result.json`; current Go messaging fault controls pass | Media-specific silent drop, separate detection/recovery timing, alternate-path recovery, restored-IPv6 stability and no-path deadline control are **NOT RUN** in both policies |
| Native IPv6-only complete app journey | Available phone/emulator remain on dual-stack access; relay global IPv6 restored | IPv4 native controls and IPv4/IPv6 host socket fixtures only | **BLOCKED** | No isolated device access route excluding IPv4/translation was available | Live routes/targets and `full-app-ipv4-artifact-evidence.json` | Full text/reply, pending-message reconnect/reopen and native call journey on native IPv6-only access remain unverified |
| DNS64/NAT64 complete app journey | Disposable network namespace on relay host was available; it had loopback only and no external route | Separate IPv4/IPv6 TURN sockets; **no synthesized DNS answer or translated flow** | **BLOCKED** | The relay namespace is a component fixture, not a DNS64 resolver, NAT64 translator or phone gateway | `relay-namespace-network.json`, `relay-isolated-results.json` | Controlled A-only service, observed synthesis/translation, Go bootstrap/message path and native media with an IPv4-only peer remain unverified |
| IPv4 TURN/UDP timeout and public reachability | Mac Wi-Fi host probes to public coturn; raw external UDP peer; Pixel/API 37 and fresh API 35 emulator native relay-only calls | After repair: UDP4/IPv4, UDP4/IPv6 and TCP4/IPv4 serial controls each 3/3 pass; native emulator-to-TURN IPv4/UDP RTP observed | **PASS** for the public IPv4 mapping repair; historical timeout cause unresolved | User-authorized one-line mapping repair applied at 20:28 UTC. All three advertised-address external-peer trials now return 3/3, as do their paired controls | `udp4-apply-20260914T202634Z/`: apply/audit, external-peer/original-condition results, relay capture joins and both native endpoint verdicts | Same-server media alone is insufficient; external-peer proof is separate. The post-repair UDP6/IPv4 comparison retains one data and one permission/channel timeout; no spontaneous native stall/recovery or explanation of the older 10/11 loss |

**Focused IPv4 UDP findings after recovery:** evidence is under
`.codex-test-logs/network-gaps-20260914/udp4-focus-20260914T191758Z/`.
Its `evidence-index.json` SHA-256 is
`c99bfc65c47fd12c6c753021905deeeeadae561584892ef307d848804f143021`;
it retains the distinct plans, first failures, artifact/source hashes and cleanup.
`original-conditions-plan.json` declares three repeats per condition using the
retained serial probe: 100-byte records, 50 sequences each direction, no pacing,
seven-second reads, no control or media retransmission, Wi-Fi `en0`, fresh
credentials/allocations and permission/channel/Refresh(0). Local UDP4/IPv4,
public UDP4/IPv4, public UDP6/IPv4 and TCP4/IPv4 each pass 3/3 with 100/100 exact
payloads. Public UDP4/IPv6 retains **75/76 then data timeout**, **100/100 PASS**,
and **allocation timeout before media**. The original UDP4/IPv4 10/11 loss was
not reproduced in these three trials, and its cause is still unknown.

The separately declared paced set fixes client-to-TURN IPv4/UDP and runs three
fresh allocation pairs each for IPv4 and IPv6 relay allocation. All six return
100/100 exact records at 20 ms pacing, seven-second drain, zero duplicates,
reordering, stale responses or control retries; all twelve allocations release.
Only STUN control transactions are eligible for bounded retries in this probe;
there is no media retransmission. Relay `ens5` captures match the exact synthetic
ChannelData marker rather than fixed NAT ports. Joining sender/sequence at the
**same capture boundary** finds every ingress and egress packet: 200 per serial
UDP4/IPv4 trial, 1,200 across the paced set, zero kernel drops, unmatched packets,
duplicates or observed mapping changes. Same-boundary ingress-to-egress maxima
are 0.842 ms (serial set) and 1.779 ms (paced set); these are not end-to-end
latencies. No claim locates the historical loss or explains the uncaptured
UDP4/IPv6 serial failures.

The public reachability defect is independently reproducible: coturn's explicit
public/private IPv4 mapping still names its previous public address. A raw
synthetic UDP peer with an authenticated TURN permission sends three distinct
100-byte records to a fresh allocation. All three **advertised-address** trials
receive 0/3 within seven seconds; all three paired **current-server-address**
controls receive 3/3 in 87–109 ms. All six allocations release. This changes a
raw probe destination, not app ICE candidates or peer identity. The existing
coturn hairpin mapping lets two allocations on this same server communicate
despite the stale advertisement; that explains why TURN-to-TURN tests can pass.
The mapping error is current and separate from the older pre-outage 10/11 loss.

`docker-ws/fix_coturn_dual_stack_tls.py --external-ip-only` changes only that
public IPv4 substring, requires an exact preview hash before application,
refuses active allocations and restores the original configuration on a failed
bounded restart. Five unit cases cover preservation, preview/hash fencing,
active calls and rollback. Actual relay preview proposes config SHA-256
`393dc7c36b824b2e562e70e28d1f13975de4777e12bbcf69106a4606e80873e6`
to `e68e61cc0b04e7fb57d27983451ae03ba162ed1cbad1782abf0904f09307a29f`.
The private one-line patch and apply arguments are retained. At the preview stage
no deployment or restart had occurred. That undeployed status is superseded by
the subsequently authorized application and verification below. No app rebuild
is required for this mapping repair.
The 20:11 UTC read-only audit finds unchanged config and running coturn executable
SHA-256 `487085a85d74e66064a4cd73f357f1e87710875d73fe8eaaa47583909cdc33ec`
on Ubuntu 24.04.2/kernel 6.8.0-1030-aws, started 16:50 UTC before these trials.
The relay executable remains `7e8927194308e91f9bab78098cbe2ff9d7db1839341daa7ef02b9fc6c036aa2b`.
The host local-control coturn executable hash is in its separate plan; do not
confuse it with the running public coturn or earlier namespace binary.
The packaged isolated relay command subsequently executes **15/15 PASS** using
that exact public-service binary (coturn **4.6.1**) in a fresh loopback-only
network namespace: three each for UDP4/IPv4, UDP6/IPv4, UDP6/IPv6, TCP4/IPv4 and
101-byte UDP4/IPv4. It returns all 1,500 synthetic records without loss,
duplication or reordering and releases all 30 allocations. The owned server,
credential config and remote directory are removed; the production network and
service are unchanged. `current-relay-isolated/results/results.json` SHA-256 is
`3d5314e8559de8baaedad5a54ca11ee4b8ffa2abaa8f101d497fbcd345e86b72`.
This closes the packaged component-execution prerequisite after SSH recovery;
it does not repair the live public mapping or explain historical Internet loss.

Native public UDP now passes the existing Android media wrapper on both pinned
endpoints: two calls in opposite caller directions, eight endpoint DTLS/RTP
phase verdicts including explicit ICE restarts, four fresh credential requests
and two closed calls per endpoint. Relay-only privacy remains enforced. A fresh
disposable API 35 guest uses the existing A-only DNS fixture for the TURN name;
its owned capture proves bidirectional RTP-bearing ChannelData over **IPv4 UDP
to TURN**. The phone's connection family is still unobserved. USB carries the
fixture's signaling/control, not TURN media. This is native media interoperability,
not the complete production app journey, audible sound, signed release or
natural fault-detection/recovery evidence. The debug APK is SHA-256
`4b117a6e5bc54ea8ae8634e48e5afd7c17c338732d5142af42a2689fb8546f86`,
built with Flutter 3.47.2, flutter_webrtc 1.6.0, Android WebRTC 144.7559.14;
exact source/config/target identities are in `native-artifact.json`.
The first family observer failed because QEMU's UDP sockets are unconnected;
the next failed by comparing QEMU timestamps with the host clock. Both failed
receipts remain. The corrected observer uses recent bidirectional media within
the capture's own clock plus host file freshness, with causal offline regressions.
The final pass has its own receipt and runner digest. Cleanup restores device
settings, removes disposable packages/DNS container and stops the owned guest;
original AVD and app data are preserved.

Focused selection metadata validates; the explicit-base local wrapper passes
**11 checks / 938 cases**, with zero skips/failures or identity gaps. It includes
the five IPv4 repair tests and seven native receipt/family-observer cases while
retaining TLS deployment preservation. Source digest is
`3ba92e8ce679cb726d103dd181ba8d006c98614b8e7840fd508a6e114003f829`,
rules digest `6cb7d771caa3f2cb9d532e5278fea94a6a0615e955864276c3307d2364e42afc`,
and `final-change-checks/results.json` SHA-256
`cad0eeb1fd0fcbcf59d484c52a2772bd0c7f8ff052bff9b59a4b8bc5c6506b51`.
The other **28 combined-selection checks remain NOT RUN**; their exact IDs are
retained in that report. No full host wave, release suite or signed artifact is
certified. The first preview using the default Flutter found an SDK mismatch;
the retained corrected preview and actual run use the resolving Flutter 3.47.2.
The same offline operations are registered for the later full validation pass.
Native execution retains its own earlier runner hash; the only later observer
change rejects a missing `-tcpdump` argument and is covered by the offline suite.

**Authorized IPv4 mapping repair, September 14 at 20:28 UTC:** after reviewing
the concrete undeployed repair, the user requested its application. The fresh
preflight found the same reviewed config hash and **zero active TURN allocation
sockets**, and verified the mapped private IPv4 was assigned. The existing
IPv4-only helper ran as a bounded transient service, backed up the configuration
and restarted coturn. It exited successfully at 20:28:11 UTC. The configuration
now has the exact proposed SHA-256
`e68e61cc0b04e7fb57d27983451ae03ba162ed1cbad1782abf0904f09307a29f`.
The post-apply audit verifies the backup matches the original, only the public
IPv4 substring changed, both running binaries are unchanged, both services are
active, and the messaging relay process was not restarted. Certificate/key and
renewal-hook hashes are unchanged. No firewall, public DNS, dependency, app or
Go relay code change was made; the earlier no-deployment instruction was
superseded only for this reviewed configuration repair.

Fresh predeclared external-peer verification passes **all three advertised-address
trials and all three paired controls**, with 3/3 unique 100-byte records each.
Every allocation now advertises the discovered current IPv4, and all six
allocations release. This is the causal before/after proof for the stale-address
defect: the corresponding pre-repair advertised-address cases each returned 0/3.
The same original serial driver then passes local UDP4/IPv4, public UDP4/IPv4,
public UDP4/IPv6 and TCP4/IPv4 **3/3 each**, 100/100 records per case. The public
UDP6/IPv4 control retains **31/32 then a data timeout**, a **permission/channel
timeout before media**, and one 100/100 pass. Its cause is unresolved; do not
combine those failures into the IPv4 passes or attribute them to the repaired
mapping without evidence. The three IPv4/IPv4 relay captures account for all
600 ingress/egress packets with no missing sequences or kernel capture drops.
All 30 original-condition allocations release. Verified host TLS hostname/chain
handshakes also pass over both families; this is not new native TLS-media proof.

The exact same debug APK `4b117a6e5bc54ea8ae8634e48e5afd7c17c338732d5142af42a2689fb8546f86`
passes the post-repair native UDP fixture on both endpoints: two calls in opposite
caller directions, eight secure bidirectional RTP phase verdicts including
explicit ICE restart, four fresh credential bundles, and two closed calls per
endpoint. The fresh owned API 35 guest capture confirms IPv4 UDP media to TURN;
the Pixel/API 37 client-to-TURN family remains unobserved. These local-broker
media-wrapper tests do not establish a full production journey, spontaneous
loss recovery, audible sound or signed-release behavior. Device settings,
disposable packages, the DNS container and owned emulator are cleaned up;
the original AVD and app data are preserved.

Post-apply evidence is under
`.codex-test-logs/network-gaps-20260914/udp4-apply-20260914T202634Z/`.
Its `evidence-index.json` SHA-256 is
`04d708100d4b789fdad46515fbb3b122db31562907b4ce86a600a08936e6d7be`;
external-peer results are `03380e1d71fc4b88423c9b57566b8a81c870d5e7f5e104772f62f0e800636572`
and the native two-endpoint result is `898df765964ac5463e4b04ca1f6b76f71f15a63782cd96aa11db54e867966158`.
The unchanged repair/probe source and existing mappings validate, then the
explicit-base local operation selection passes **3 checks / 91 cases** with
zero identity gaps; **36 other combined-selection checks remain NOT RUN** in
that report. Earlier 938-case evidence retains its own report. The current
source/rules digests match that earlier final run; no full wave/release suite
was rerun for this configuration-only application. The old 10/11 timeout is
still unexplained; this verified fix closes the separately reproduced current
IPv4 advertisement defect.
`operation-checks/results.json` SHA-256 is
`b1a95c38adef4fcc17413fcac51d8de57ca950f658aea6a4cb5194b659625209`.

The retained original capture was actually decoded: at 08:43:04–08:43:11 UTC
it contains ten ChannelData frames toward TURN and ten from TURN, sequences
0–4 from each endpoint, with zero kernel capture drops. The next payload was
outside that fixed mapped-port capture filter's observations. This does not
locate loss or exclude a NAT mapping change. Capture SHA-256:
`26a82ca3ba7b9a13e0d7a8076b610ce691d2e75c60737ad38c050d6a8533fd6b`.

Fresh trials were declared **three per condition**, not retried until green.
The original serial probe uses 50 sequences per direction, 100-byte payloads,
no deliberate pacing, seven-second reads, fresh allocations, explicit
permission/channel binding and Refresh(0). Local IPv4 UDP passed 3/3; public
UDP4/IPv4 completed 1/3, with two credential-stage failures. The public TCP
control completed 1/3. The other original public cases stopped at credentials
or allocation. The new paced default-credential campaign (three UDP4/IPv4
trials) and the explicit-IPv4-credential campaign (three each for UDP4/IPv4,
TCP4/IPv4 and UDP4/IPv6) all stopped at credentials. Their failures remain
separate, with no claim that later standalone credential success explains them.

At the user's request, execution moved to the relay host's **isolated network
namespace**, without changing its normal network. The installed coturn binary
served only that namespace's IPv4/IPv6 loopbacks with a generated credential.
Fifteen trials passed: three each for UDP4/IPv4, UDP6/IPv4, UDP6/IPv6,
TCP4/IPv4 and non-aligned 101-byte UDP4/IPv4, at 20 ms pacing. Every endpoint
received its 50 exact payloads without loss, duplication or reordering, and all
30 allocations were released. The server process and private directory were
removed. This is real Linux TURN component evidence, not device access-network,
NAT64, production signaling or native audio proof.
The actual runtime log identifies coturn **4.6.3**, using
`/usr/local/bin/turnserver` on the Ubuntu 24.04 relay host. The initial private
driver did not collect the executable or copied whole-probe digest; that
artifact-provenance limitation remains. The packaged runner now records both
digests, but its first relay execution was blocked at SSH, including the bounded
14:13:47 UTC availability check. The later packaged execution against the exact
production binary is recorded in the focused findings above. Earlier relay result SHA-256:
`ff387cc89d98f9affc1d94aa7cac817b39f26bbff626aaeb27895b92034a50bf`.

The diagnostic now lives in `integration_test/scripts/turn_path_probe.py`:
UDP preserves datagram boundaries and accepts optional ChannelData padding;
TCP/TLS retain buffered padded framing. Control requests demultiplex stale
responses and media, validate authenticated responses and retry only STUN
transactions within the same deadline. Media is never retransmitted. Both
socket boundaries retain sequence/timing observations, loss, duplication and
reordering, with bounded traffic and cleanup. The failing unpadded 101-byte
counterexample is retained separately from the historical 100-byte timeout.

Earlier local native controls used APK SHA-256
`53a53099902aa9f45f2c0c4788fb9ab1a088ca7846d6062002e9b6eb7999a0e6`:
both endpoints passed all eight policy/direction cases and their explicit ICE
restarts, with 32 secure bidirectional RTP observations and closed calls. These
explicit fixture restarts do not exercise natural loss detection. The existing
full-app adapter separately built/tested APK
`a7acee8b191cfe76fb4bb6a9acc55daaa4fd72031884a8ea0398682a59afc552`
and passed 27 assertions for one emulator-to-phone production-entrypoint call,
including contacts, native Answer, per-endpoint RTP, controls and cleanup;
the Pion known-Opus oracle passed separately. Native public UDP failed before
media: both credential requests were rejected, both driver exits were zero and
both endpoint receipts were absent. It is not an audio timeout or a no-path
recovery control. Human-audible sound and signed-release behavior were not tested.

After metadata validation and an explicit-base local change preview, the earlier
focused wrapper run passed **11 checks / 931 cases**, with no failures, skips
or identity gaps. Its source digest is
`86de664984a5ee22e5e68819eacd57813b07bb0b8a30ba9172b4a1f1874710ca`;
`closure-change-checks/results.json` has SHA-256
`132ff358d57084b3fe141c5d05add6c29f0ac4dc68787daf2febce4d783d445c`.
The combined working-tree selection also contains **26 NOT RUN checks**,
including broad affected host families, whole Go modules and complete device
lanes; their exact IDs remain in that report. Overall wrapper status remains
**NOT RUN**, not a complete change/release pass. Separate targeted Go and native
receipts above retain their own source/artifact identities. No full `host-all`,
release sweep or signed candidate validation was executed for this test-only
follow-up. Initial failures were preserved rather than overwritten.

### Executable continuation and missing prerequisites

The packaged relay component fixture requires Linux, `ip`, the full Python 3
standard library and the existing coturn binary. Run it only inside a disposable namespace; it rejects
any namespace with an interface other than loopback **before mutation**:

```sh
# On the relay, in an owned private staging directory containing the script:
sudo -n timeout --signal=INT --kill-after=5s 55s unshare --net \
  python3 turn_path_probe.py --local-fixture \
  --turn-server /usr/local/bin/turnserver --output "$PRIVATE_RESULTS"
```

Retain its plan/results/cleanup before deleting the owned stage. The initial
15-trial relay execution used the retained private driver and the same probe
core; the first packaged-command attempt was blocked at SSH before execution.
After recovery the packaged command passes 15/15 with the exact running
production binary, separate plan/result hashes and complete cleanup as recorded above.
Its host guard tests are separate evidence. The wrapper and network fixture
never restart production coturn or alter host firewall rules.

The packaged command's local container attempts remain unsuccessful evidence:
the first lacked Python's `hmac` module; after supplying the full standard
library, Docker's network-none namespace still exposed nine down tunnel
placeholders in addition to loopback. The strict interface guard rejected that
namespace before starting coturn or running trials. It was not weakened. The
image identities, topology and both failures are retained separately from the
successful relay-host execution. Neither local attempt exercised NAT64.

For public diagnostics, reuse the existing validated JSON-line credential
client and resolve the explicit endpoint/interface from the live network:

```sh
python3 integration_test/scripts/turn_path_probe.py \
  --server "$TURN_IPV4" --control-family 4 --allocation-family 4 \
  --transport udp --interface "$TEST_INTERFACE" \
  --credential-command "$CREDENTIAL_CLIENT" --trials 3 \
  --output "$PRIVATE_RESULTS"
```

Continuing the three IPv6 application scenarios requires (1) a reachable IPv6
relay/TURN service, (2) an isolated **device-facing** IPv6 access segment whose
route/DNS/firewall observations exclude application IPv4, cellular, VPN and USB
forwarding, and (3) a separately configured DNS64 resolver/NAT64 translator
reachable from that segment for the translation trial. A relay-host namespace
alone supplies none of the phone-facing routing. An IPv4 deny rule on a public
server also cannot exclude direct peer or another-interface bypass.

On an authorized dedicated gateway, enable IPv6 routing/DNS for the native
trial; disable IPv4 application forwarding, DNS64 and NAT64. For the separate
translation trial, supply a controlled A-only service view, enable DNS64/NAT64,
record the synthesized AAAA and translated flow at the same test boundary, and
retain real peer/hostname verification. For available iOS devices, Apple's
[current IPv6 guidance](https://developer.apple.com/support/ipv6/) requires
excluding cellular bypass. Its [current NAT64 setup procedure](https://support.apple.com/en-lamr/guide/mac-help/-mchlp1540/mac)
uses General → Sharing → Internet Sharing, then Option-clicking its Info
button and enabling Create NAT64 Network; it needs a separate usable uplink and shared
interface. This Mac had no authorized spare access/uplink arrangement and no
passwordless administration, so that procedure was not executed. Prefer the
requested relay-host arrangement once its routed test segment actually reaches
the devices. Never relabel either server isolation or ordinary IPv6 sockets as
completion of those journeys.

## APNs is a separate boundary

Retain the committed investigation in [TESTING.md](../docs/testing/TESTING.md):
provider-accepted sandbox calls sometimes missed while the device was suspended;
complete private archives attributed failed development courier connections to
IPv6 and later reconnections. The September 14 archive recheck confirms that
the September 12 return-to-Wi-Fi connection **C552 used IPv6 TCP 443**, while the
unrelated C551 used IPv4 TCP 5223. C552 negotiated the APNs ALPN at 13:05:14 UTC;
its cancellation followed the development keep-alive failure at 13:16:58 UTC.
Do not generalize the earlier C542/5223 observation to every trial. The complete
all-courier exports and a redacted attribution receipt are retained with this
review's private evidence. Some IPv4 trials passed. The hotspot also
changed the local path and did not isolate IP version. The app's repaired
retired-predecessor journal handoff is independently testable and cannot repair
a push that the OS has not delivered. No permanent IPv6/APNs fix is established.

Reuse the existing six-minute idle procedure, preserving separate trial IDs:

1. Record exact signed artifact hash, build configuration, OS/target, actual
   `aps-environment`, bundled `MknoonVoipEnvironment`, bundle ID and VoIP topic.
   Debug/Profile use development; Release uses production in current project
   settings. Verify the **signed** app with
   `scripts/verify_ios_voip_signing.sh <Runner.app>`; project settings alone are
   insufficient. Decode the embedded provisioning profile, check its device,
   application/team identifiers and expiry, and compare the installed native
   token/topic/environment/epoch with the current authenticated recipient's
   relay registration. Record the checkout, comparison base, existing edits and
   retained artifact hashes. Keep development and production trials separate;
   a Profile build signed for development is not a distribution candidate.
2. Establish the last successful VoIP receipt, then confirm suspension and wait
   at least six minutes without calling, foregrounding, polling app-owned code
   or otherwise waking it. Observe suspension through the existing native/UI
   harness. Record screen-lock, Focus, power, debugger and network conditions.
   Audit observation tools: container copies and diagnostic service startup
   belong before/after the interval, not inside it. Predetermine the small
   repeat set and require a successful control with clean termination first.
   Use monotonic durations within each run/clock domain; retain measured clock
   offset bounds before comparing phone/server wall timestamps.
3. Send one synthetic incoming call on isolated accounts. Correlate exact
   provider acceptance/response identifiers and UTC timestamps with device
   PushKit callback, CallKit report completion/presentation, native/Dart adoption
   and media. Provider acceptance is not device receipt; aggregate counters do
   not identify a trial. Preserve the missed first attempt and caller deadline.
   Any immediate retry is a different trial.
4. Exercise cancellation/expiry and late arrival without reviving stale calls.
   Exercise the unadopted retired predecessor through existing regression
   fixtures or an ordinary authenticated cancelled call, never invented journal
   rows. Acknowledge its exact durable terminal receipt and verify that successor
   audio/timeouts remain owned. Fake-platform XCTest is separate from live OS
   presentation.
5. Attribute the **exact** development/production `apsd` courier connection for
   the trial from the complete private archive, including connection ID,
   process/environment, timestamps, interface, family, port and reconnects.
   DNS answers, a cached numeric address or an unrelated system connection are
   insufficient. Keep raw native evidence private; share only redacted findings.

Apple's current [Push Notifications Console documentation](https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console)
provides development delivery logs for up to seven days, queried with the
response's `apns-unique-id` and selected bundle ID. Use authorized account access
and retain the downloaded log; production aggregate metrics are not per-trial
courier attribution. Use Apple's current
[APNs profiles and logs](https://developer.apple.com/feedback-assistant/profiles-and-logs/)
and associated sysdiagnose instructions for further collection. No private API,
app wake loop, global IPv6 disable or router/user DNS change is an app repair.
The reviewed `74ecbafe` HTTP provider discards response IDs. The same revision
was independently verified in the running relay binary on September 14 after
its public IP changed; a local source change does not update that service.
`apns_voip_receipts.go` now provides optional capture of actual HTTP status,
returned `apns-id` and returned `apns-unique-id` in the existing private call
diagnostic store. The existing `ios_notification_provider_adapter.py` captures
headers for a development **alert** control; it is not the authenticated VoIP
provider and must not substitute for this journey. Per Apple's
[APNs response documentation](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns),
`apns-unique-id` is development-only. Missing production IDs are normal;
missing/malformed IDs never change delivery or retry classification. Locally
generated attempt IDs are explicitly separate from Apple response IDs.

Capture defaults off. A separately approved provider deployment can opt in with
`APNS_VOIP_CAPTURE_OWNER_SHA256` (the existing `diagnosticPrivateKey` of the
authenticated, consenting isolated caller) and `APNS_VOIP_CAPTURE_UNTIL`
(RFC3339, future and at most 30 minutes from startup). The monotonic deadline,
32-response process/record caps, consent epoch and existing queue/storage quotas
bound capture. `apnsResponsesPrivate` stays in protected 0600 records inside the
0700 diagnostic directory, outside shared events/operator reports; existing
14-day retention and consent withdrawal purge it. Disk/queue/observer failure
must not delay provider delivery. No tokens, JWTs, private keys or payloads are
copied. Retain private receipts with an explicit expiry; share redacted stages.
Existing call trace IDs cannot reconstruct an Apple identifier. No Console
delivery log was retrieved in this investigation. This capture closes an
evidence gap, not a demonstrated push-delivery defect.

The September 14 physical repeat set is retained in
`.codex-test-logs/apns-idle-20260914/REPORT.md`: iPhone 13 Profile 1.0.1(120),
verified development signing/current sandbox registration, and Pixel 6 Debug
1.0.1(121). All four predeclared idle calls presented (two unlocked, two locked;
389.6–522.8 seconds suspended). Three completed answer/media/cleanup; the first
locked call reached no-answer after the automation answered too late. Preserve
that failure and the separate initial control locator failure. A user-unlocked
setup window was restarted before sending. Native callback-to-report durations
were 46–55 ms for the idle calls. Current courier family and Apple delivery logs
are unknown, production delivery is untested, and the receipt candidate is
prepared but undeployed. The live relay at the user-supplied new IP still runs
the reviewed binary. These observations do not explain the historical misses.
Check the existing diagnostic quota before a trial: the isolated caller's first
control records lacked events at its 5 MiB owner cap. Archive existing evidence
before an authorized normal in-app diagnostic clear; preserve later truncation
fields and reserved terminal/media summaries instead of treating missing rows
as absence of delivery.

The retained PushKit registry in `AppDelegate` and `MknoonVoipPushRegistry`
reports required pushes before Flutter, relay lookup, TURN or audio. Legacy
callbacks require reporting; iOS 26.4 metadata callbacks follow Apple's
[`mustReport` distinction](https://developer.apple.com/documentation/pushkit/pkvoippushmetadata/mustreport).
Stale/cancelled invitations still receive required OS reporting without gaining
new logical authority. Keep completion exactly once and preserve duplicate,
disabled-capability, late-arrival and successor ownership tests. The provider's
bounded retries retain the original invitation expiry and cancellation authority;
chat recovery TTLs are not call policy. Classify rejection, accepted/undelivered,
inconclusive callback evidence, report failure, system-disallowed presentation,
adoption failure and post-answer media failure separately.

For escalation, retain the signed identities, exact UTC first-attempt timeline,
provider response/delivery log if available, full native sysdiagnose, courier
connection attribution and the unchanged/mutated network variables. Network/OS
owners can inspect idle-state expiry, routing, ICMPv6/PMTU and packet loss on an
explicitly authorized isolated network. Apple's
[APNs network requirements](https://support.apple.com/en-gb/102266) describe device
5223 and 443 fallback without TLS interception. Prepare an Apple Feedback or
network-owner escalation package; submitting it requires separate authorization.
Unresolved APNs attribution does not prevent unrelated repository checks.

## Candidate and compatibility gates

The authoritative native build entry points are
`scripts/ensure_go_android_bindings.sh`, `scripts/ensure_go_ios_bindings.sh`,
`scripts/gomobile_binding_inputs.sh`, `go-mknoon/Makefile`, Android `buildGoAar`
and the iOS Podfile build phase. Their hashes include production Go inputs,
local replacements, toolchain and platform tooling. Both original stored input
fingerprints were stale and were rebuilt with pinned Go 1.25.0; the rebuilt
fingerprints match. Export-name verification alone would not prove freshness.
The NSE framework deliberately uses the separate `nse_lite` build.

Use Flutter 3.47.2 from the resolved package configuration, not the older default
PATH. iOS signing uses `scripts/build_ios_appstore_ipa.sh`,
`ios/ExportOptions-AppStore.plist` and
`tool/build/voice_call_release_defines.json`; retain its unique archive, dSYMs,
IPA and provenance. Android release signing is owned by
`android/app/build.gradle.kts`; no debug signing substitute is permitted for
release acceptance. Preserve previous outputs before either build.

The new **local, unpublished** artifacts are version `1.0.1`, build `120`:

| Artifact | Retained location | SHA-256 |
| --- | --- | --- |
| Signed App Store IPA | `build/releases/1.0.1+120/ios-20260913T230927Z-0aaaeaef191c4e44b4338a093c4f8479/mknoon.ipa` | `9c00c7c47fa0fd8e76f25c656bdbabf8d2fa645a6607ccba4b6e43f7361eb552` |
| Signed Android AAB, rebuilt with WebRTC `.14` | `build/releases/1.0.1+120/android-turn-tls-20260914T132035Z/app-release.aab` | `7f1d4e8fcb5c24cf6654620fe0c4b708ecb7bb4e053e7e56d7b9ec9a32a73018` |
| Linux amd64 relay executable | `.codex-test-logs/dual-stack-priority4/relay-server-linux-amd64` | `ab9e9bb167b58db93a8b7ee3fab26e78f25765b7041e33109ad7d6c77ccdd982` |

The extracted IPA passes the existing signature/environment verifier. Its signed
`aps-environment`, embedded profile and bundled environment all say `production`;
application identifiers agree, the profile matches the signing team, and
debugger attachment is disabled. Its bundle is `com.mknoon.app`, hence the
runtime VoIP topic is `com.mknoon.app.voip`. This App Store profile has no device
list and is not proof of a locally installed candidate. The retained iOS
provenance reports unchanged build inputs and preserves its archive and dSYMs.

The user subsequently requested Android build 120 with the repaired native
dependency. The current AAB above and the default
`build/app/outputs/bundle/release/app-release.aab` are identical. All three
WebRTC native slices exactly match the published `144.7559.14` AAR; the release
DEX retains `PlatformCertificateVerifier.verifyServerChain([[B)Z` for JNI.
Its adjacent `provenance.json` records the build, signature and binary checks.
The earlier `.09` AAB at `build/releases/1.0.1+120/android-priority4/app-release.aab`
(SHA-256 `59880ecc38ae8727bc9a1e3d1bf84ac7602f9bacc0f619f87659b5cd15e79927`)
is preserved for comparison and superseded as the current Android candidate.

The rebuilt signed AAB manifest reports `com.mknoon.app`, `1.0.1`, code `120`.
Java's verifying `JarFile` read all 389 signed entries with zero unsigned payload
entries; signer certificate SHA-256 is
`5eaa7a55b8daa81ea3399c8931f38c0b5ad2c314cec0f82955cdfa435630142d`.
`jarsigner -verify` succeeds, with retained self-signed-chain, timestamp and ZIP
metadata/order warnings; this is not Play upload acceptance or proof of the
published signing identity. The current Android AAB's adjacent provenance retains
its command, source/configuration identity, native slices and signature checks;
`candidate-artifacts.json` remains the original campaign's record. The Linux
relay was cross-compiled locally, not executed on or installed to production.

The previous published revision/artifact is still unresolved. A fresh candidate
cannot supply that baseline. A read-only GitHub release query returned no
distribution records. Current read-only device inventories find developer-built
`1.0.1(119)` on two available iPhones; the third device query timed out. These
observations identify neither the signed `1.0.1(120)` IPA nor a published baseline.
Upgrade a populated isolated installation of the
**actual previous published build** in place, retaining keys, accounts, contacts,
groups and history; do not clear data. Host SQLite migration/schema 119 tests
prove a separate boundary. Run old/new peers in both directions and exercise
ordinary traffic, quiet sender rejection by old relays, old-recipient retention
until upgrade, and new-relay/new-recipient quiet display suppression. A relay
update alone cannot certify native Go projections, Dart policy or old binaries.

Selection and required assertions live in `tool/testing/selection.json`.
`validate`, explicit-base `plan --mode change --local` and `run` retain all
selected omissions/failures. The integration boundary runs the existing
`host-all --batch-flutter --dart-only` sweep once, with Go module checks owned by
the wrapper; native XCTest is executed separately. No syntax-only native test is
reported as executed. Release selection still needs the actual published base,
exact signed artifacts and all required candidate evidence. Passing repository
checks or producing signed bytes is not release acceptance.

The integration Dart sweep completed with 16,803 passes, 13 skips and one
failure: `group_private_media_safe_disabled_boundary_test.dart` timed out before
the expected ordinary download began. Its separate three-test diagnostic passed
without a code change; the full sweep remains failed. The current simulator
XCTest run executed 79 tests with zero failures, including retired predecessor
audio ownership, pending native call storage and the targeted NSE authority
boundary. This is executed native test evidence, separate from signed-device
PushKit/CallKit presentation. Logs retain the first build/test failures and all
diagnostic results; they are not overwritten by successful retries.

The explicit-base change wrapper completed with 43 PASS and five BLOCKED
selections. Four remain incomplete because tests skipped: conversation (10),
push (1), storage (1) and Go core (2). Their executed cases had no failures;
Go core recorded 1,843 passes and relay recorded 1,286 passes. The initial
device-audio prerequisite block was subsequently exercised through the existing
local production-call adapter, and the wrapper's SIMS verifier accepted its
27-assertion report (`device-audio-supplement.json`). The original wrapper result
remains retained. Quiet recovery recorded 460 passes; migration 17; the tagged
old/new recovery/IPv4-relay command passed. A focused current native socket run
executed 14 fallback/address/recovery cases without skips and retained its raw
output in `native-ipv6-faults.log`. Full per-check commands/results are in
`change-checks/plan.json` and `results.json`; the release preview explicitly
blocked on the missing published baseline rather than substituting the review
base. No full suite was repeated after these focused diagnostics.

## Quiet protocol admission: initial gap and completed relay deployment

A fresh authenticated, deliberately incomplete request (no recipient or payload,
therefore no stored row or push) returned `Unknown action: store_quiet_v1` and
`Unknown action: store_custody_quiet_v1` from the relay before redeployment.
`public-quiet-admission.jsonl` preserves that response. That earlier v1.10.7 had
quiet support, but its version label did not certify the new action-level
contract. New clients must retain these failed
recovery obligations until a compatible relay is available; they must not retry
the same automatic quiet send through an old action that drops the sidecar.

The user-authorized relay-only update completed September 14 at 11:34:32 UTC.
Go 1.25.0 built clean merge commit `74ecbafeec31cf92c5efd1137f9feac85b2a855b`
for Linux/amd64 with CGO disabled, `-trimpath`, and
`-X main.callDiagnosticBuild=74ecbafeec31cf92c5efd1137f9feac85b2a855b`.
The staged file and running process both have SHA-256
`7e8927194308e91f9bab78098cbe2ff9d7db1839341daa7ef02b9fc6c036aa2b`.
The unchanged v1.10.7 label alone cannot distinguish these binaries.

The existing `go-relay` selection passed 1,286 cases with no failures/skips;
the diagnostic subset leaves other release checks `NOT RUN`. The exact Linux
binary also started and shut down cleanly in an existing, network-isolated
Docker fixture with disposable memory storage. Production validation then
passed all six TCP/WSS/QUIC mixed-family pairings, including both quiet actions,
ordinary traffic, signed rendezvous/reservations, authenticated sender/byte
preservation, old-reader retention and call-control store/retrieve/ACK. Existing
ordinary and protected test rows survived the restart and were acknowledged;
Redis's process identity, relay identity/configuration and IPv4/IPv6 listeners
were preserved. nginx and coturn process identities were unchanged.

The first deployment attempt automatically restored the old binary because a
three-second log guard expired before initialization emitted readiness. That
failure is retained; the old relay's subsequent startup took about 24 seconds.
The corrected guard waits up to 60 seconds for the expected peer and durable
backend summary from the current PID, verifies the executable digest and follows
with authenticated public requests. No service initialization error was observed.
The initial retention probe also assumed one legacy row; the protected row's
compatibility shadow correctly made two. The corrected probe checks both exact
owned rows, with the failed fixture receipt retained.

Private evidence is under `deploy-20260914T1123Z-74ecbafe/` inside the existing
ignored evidence root: `candidate.json`, `relay-checks/results.json`,
`before.json`, `after.json`, `activation-attempt2.log`, `retention-after.jsonl`
and `public-application-matrix.jsonl`. The root-only rollback directory on the
relay is `/var/backups/mknoon/relay-20260914T1123Z-74ecbafe-attempt2`.
It preserves the previous binary (SHA-256
`3b943a329c0ed9cb4ed3401bfddc5b42bf94707fab054bd9ec40d402016c9873`), unit,
drop-ins and environment files. Its `rollback.sh` verifies and atomically
restores only that binary and restarts only `relay-server`; Redis and configuration
are left intact. The first attempt exercised this same rollback operation.

An older relay rollback restores ordinary service but cannot complete new quiet
obligations; clients must retain them for later safe delivery. Do not erase them
or loosen old/new protocol admission to make a rollback appear complete.
This deployment does not establish signed-client behavior, audible calls,
previous-published-build compatibility or a fix for sandbox APNs idle misses.

## Remaining operational changes and rollback boundaries

No duplicate IPv6 activation is proposed: current public TCP/WSS/QUIC paths are
working. The quiet protocol admission gap was closed by the relay update above.

### Native TURN/TLS: proven Android repair, not published

The follow-up found the same valid leaf and complete chain over IPv4 and IPv6 on
TURN/TLS 5349 and, independently, nginx 4001. The leaf is valid September 7 to
December 6, 2026, with SAN `mknoun.xyz`. The chain is leaf → YE2 → Root YE
cross-signed by X2 → X2 cross-signed by X1. Served bytes match coturn's
`/etc/coturn/tls/fullchain.pem` and Certbot's current `fullchain9.pem`.
Public-key hashes match the configured keys; coturn's copies are
root:turnserver 0640. Expiry, name, chain completeness/order, key mismatch and
stale copies/reloads are refuted for these dated observations.

The exact `.09` Maven AAR matches its upstream release SHA-256
`34cf91dd7497e5fe88adb76ba29ccae35db42dd6614ce548b79ce037b6d634d5`; all three
bundled native ABIs match the retained before APK. Every certificate in the
previously extracted bundle (SHA-256
`f698d5011d2f24fb4cb9fdbdf0d619325ba3751a5d97b8114d423158afadc28d`) matches DER
bytes in that binary and the 36-entry upstream `ssl_roots.h` set generated from
GTS's 2023-05-09 bundle. Neither X1 nor X2 is present. Both current listener
chains fail against this unmodified bundle at X2, with server intermediates
passed only as `-untrusted`. Adding either X1 or X2 separately to offline control
inputs passes; neither control was installed on a device. Both tested Android
system stores already validate the chain. This establishes why host tests passed
while the old native runtime failed.

The CA's current [YE2 chain options](https://letsencrypt.org/ca/certificates/)
all terminate at ISRG anchors absent from `.09`; the server already sends the
default X1-compatible chain. Another offered chain cannot repair this runtime.
No certificate was issued, replaced or appended.

`android/build.gradle.kts` now resolves only `io.github.webrtc-sdk:android` to
`144.7559.14`, the first published Android M144 patch with
[upstream platform trust fallback](https://github.com/webrtc-sdk/webrtc/commit/b9233c36a29b03f99ba4d8516774259c34ba347a).
Its AAR SHA-256 is
`44c243bb0c6ac5b0a4425e6211f7994b0d60df3cf2f5721c20c6a88aa1a68f64`, with release
source `df1011beabae993c555f7c11a7a4b8e8fa62480d`. It retains the 36 anchors and
validates the **whole** chain through Android's trust manager when built-in
validation fails. Native hostname checks remain enabled. This published patch
also contains Android audio fixes; it is not a one-commit custom rebuild.
`flutter_webrtc` 1.6.0, Flutter, Go, application call code/policy and iOS/desktop pins are unchanged.
iOS still resolves `.09`; no iOS TURN/TLS repair or parity is claimed. A mutable
`m144_release` source URL cannot identify the old `.09` binary's trust behavior.

The fresh before run reproduced `all-relayOnly-0` failing on both endpoints with
no selected pair; both drivers exited zero. The retained APK's relevant call,
credential and harness sources are unchanged between its recorded `8e6a569`
source and the reviewed base. After the Android pin change:

- TLS-only relay/relay passes eight endpoint observations: two fresh calls in
  opposite directions and their restarts, one advertised `turns:` URL, fresh
  credentials, native `relayProtocol=tls`, platform chain validation, sanitized
  egress and advancing bidirectional RTP. Peers close between calls.
- Full mixed-policy TLS passes all 32 endpoint observations, including the
  formerly failing scenario, normal direct peers and protected local TURN.
- Wrong hostname: four fresh connections reject after platform chain validation
  at the native TLS name check. Untrusted self-signed fixture: four reject at the
  native platform trust check; its listener sees eight `unknown_ca` alerts and
  zero accepted handshakes. No user certificate or verification bypass is used.
- Separate IPv4- and IPv6-isolated emulator runs each pass eight endpoint
  observations, including both calls and restarts. The resolver admits only the
  required family; independent owned QEMU/netsimd socket observations confirm
  that family on the emulator-to-TURN connection. Selected allocation/candidate
  addresses are IPv4 in both runs. The physical peer's TURN socket family
  remains unknown. Initial observer and IPv4 DNS-isolation failures are retained;
  neither is attributed to certificate validation. Emulator Wi-Fi/private DNS
  settings were restored and verified after the single-network proofs.
- Full TCP and UDP preservation matrices each pass 32 endpoint observations,
  with 16 fresh credential requests and eight closed calls per endpoint. TCP has
  24 local TCP relay and eight direct observations; UDP has 16 local UDP relay
  observations, including every protected endpoint. Normal policy still allows
  direct paths. The TLS matrix's direct local candidates were IPv6; the TCP/UDP
  preservation matrices' direct local candidates were IPv4. Unknown remote
  candidate families are retained as unknown. Every observation has advancing
  bidirectional audio RTP and DTLS readiness.

This is native media through unchanged public coturn with isolated signaling,
not a browser/host handshake. No production certificate, service, DNS/firewall or
app publication was changed by this repair. These debug artifacts do not
certify signed distribution, human-audible sound or iOS. Android build 120 was
subsequently rebuilt at the user's request and its signed AAB now contains `.14`,
as verified above; the earlier `.09` artifact remains preserved. Packaging and
signature verification do not certify signed-device media. Exact per-endpoint,
family, preservation and check results are retained with the follow-up's private
evidence and summarized in [TESTING.md](../docs/testing/TESTING.md).

### Renewal guard: prepared, not deployed

The active owner is Certbot 2.9.0's existing timer and
`/etc/letsencrypt/renewal/mknoun.xyz.conf` (nginx authenticator/installer, ECDSA,
production ACME directory, default chain). Its existing deploy hook
`/etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn` copies the two files
independently without preflight, then sends SIGUSR2. The original hook SHA-256 is
`3a3e2678e8297235aafa1724bf8896d996c3244ffb68f0cea9949105c8d245c3`.

`docker-ws/50-mknoon-coturn` is a replacement for that same hook, using
`docker-ws/coturn_tls_deploy.py` to validate a protected snapshot before switching
one certificate/key generation. It checks public trust, hostname, validity,
order and key match; intermediates remain untrusted inputs. It signals only
coturn, checks the served leaf on both loopbacks and restores the prior
generation on a failed reload/probe, still reporting failure. Keys remain
root:turnserver 0640, with protected rollback generations. No new timer exists.

The deployment preflight bundle is the intersection of each tested Android
system store plus the unchanged native roots: 140 anchors, SHA-256
`ef6088d20a02aeadd843ea7b28b725fa9219ec01453900cb7d7c8ea2795335d4`.
It is derived from actual runtime anchors, never the served chain, and never
installed on clients. The existing default X1 chain is correct. A future
unsupported root transition must fail the hook and require fresh native proof;
monitor rejection before the retained certificate expires.

Offline invalid-replacement/rollback tests pass. A local coturn test also
preserved its process and an existing TLS STUN-binding stream across SIGUSR2,
served the new leaf to fresh connections, and rejected bad input before any
promotion/signal. Its synthetic CA proves hook mechanics only. Production
coturn 4.6.1's signal handler is separately verified in
[its source](https://github.com/coturn/coturn/blob/4.6.1/src/apps/relay/mainrelay.c).
Live installation/reload remains unexecuted. Exact staging, protected backups,
validation and rollback are in
[turn-operations.md](../go-relay-server/docs/turn-operations.md#staged-atomic-certificate-hook-not-executed).

For a future authorized relay/configuration change:

1. Capture the active binary/configuration hashes, unit/drop-in precedence,
   IPv4 and IPv6 sockets, certificate chain, DNS TTLs, cloud/host ACLs and current
   sessions. Keep rollback bytes and existing account/custody data.
2. Validate the candidate offline with existing fixtures, then on an isolated
   endpoint with the expected peer identity and configured transports. Check
   exact bound IPv6 admission, TLS proxy, coturn family-specific relay addresses,
   the configured allocation range and scoped firewall rules. Keep WS upstream
   and admin/metrics exposure separate from public client ports.
3. Preserve IPv4 throughout. Stage listeners/proxy/TURN before any new AAAA or
   DNS IPv6 advertisement, validate externally per family, and promote only the
   demonstrated protocols. Do not route TURN through an HTTP-only proxy.
4. Account for relay restart disconnecting signaling sessions and reservations;
   a coturn restart separately destroys its allocations. Drain or schedule those
   disruptions and observe actual reconnect/content/media outcomes. Quiet store
   actions require compatible relay admission; rollback must fail safely rather
   than discard the quiet sidecar on an old relay.
5. If reverting DNS, withdraw the faulty advertisement and restore the known
   working configuration while keeping service available for cached AAAA,
   peerstore addresses and established sessions through the measured drain
   window. DNS removal is **not immediate fallback**: authoritative/recursive/OS
   caches and existing sessions outlive the edit. Do not remove IPv6 listeners
   or firewall allowance solely because an AAAA record was deleted.
6. Observe IPv4 preservation, custody/data retention, fresh connection selection,
   credential issuance/allocation/media and APNs separately. Record any
   unexecuted deploy/reload/firewall/DNS steps as unexecuted.
