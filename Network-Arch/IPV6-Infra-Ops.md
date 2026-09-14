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
| Current Android native TLS | Ordinary direct cases passed; first protected `all-relayOnly-0` case failed ICE gathering/exchange with no selected pair despite fresh validated credentials | Host TLS success does not certify this native dependency. Both Flutter drivers exited zero, but the existing harness correctly returned FAIL from endpoint receipts |
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
   insufficient. Keep development and production trials separate.
2. Establish the last successful VoIP receipt, then confirm suspension and wait
   at least six minutes without calling, foregrounding, polling app-owned code
   or otherwise waking it. Observe suspension through the existing native/UI
   harness. Record screen-lock state separately.
3. Send one synthetic incoming call on isolated accounts. Correlate exact
   provider acceptance/response identifiers and UTC timestamps with device
   PushKit callback, CallKit report completion/presentation, native/Dart adoption
   and media. Provider acceptance is not device receipt; aggregate counters do
   not identify a trial. Preserve the missed first attempt and caller deadline.
   Any immediate retry is a different trial.
4. Exercise cancellation/expiry and late arrival without reviving stale calls.
   Seed the existing unadopted retired predecessor sequence, acknowledge its
   exact durable terminal receipt and verify that successor audio/timeouts
   remain owned. Fake-platform XCTest is separate from live OS presentation.
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
The current HTTP provider retains status/retry classification but discards the
`apns-unique-id` response header. Existing call trace IDs and provider-acceptance
receipts cannot reconstruct that Apple identifier. Before a future authorized
trial, arrange a private, narrowly scoped provider response-header capture and
retain its association with the trial; do not fabricate a Console lookup from a
call trace or expose device tokens/JWTs. No Console delivery log was retrieved
for this review, and this diagnostic gap is not a push-delivery fix.

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
| Signed Android AAB | `build/releases/1.0.1+120/android-priority4/app-release.aab` | `59880ecc38ae8727bc9a1e3d1bf84ac7602f9bacc0f619f87659b5cd15e79927` |
| Linux amd64 relay executable | `.codex-test-logs/dual-stack-priority4/relay-server-linux-amd64` | `ab9e9bb167b58db93a8b7ee3fab26e78f25765b7041e33109ad7d6c77ccdd982` |

The extracted IPA passes the existing signature/environment verifier. Its signed
`aps-environment`, embedded profile and bundled environment all say `production`;
application identifiers agree, the profile matches the signing team, and
debugger attachment is disabled. Its bundle is `com.mknoon.app`, hence the
runtime VoIP topic is `com.mknoon.app.voip`. This App Store profile has no device
list and is not proof of a locally installed candidate. The retained iOS
provenance reports unchanged build inputs and preserves its archive and dSYMs.

The actual signed AAB manifest also reports `com.mknoon.app`, `1.0.1`, code `120`.
Java's verifying `JarFile` read all 389 signed entries with zero unsigned payload
entries; signer certificate SHA-256 is
`5eaa7a55b8daa81ea3399c8931f38c0b5ad2c314cec0f82955cdfa435630142d`.
`jarsigner -verify` succeeds, with retained self-signed-chain, timestamp and ZIP
metadata/order warnings; this is not Play upload acceptance or proof of the
published signing identity. Per-artifact provenance and `candidate-artifacts.json`
retain the build commands, source/configuration identity and checks. The Linux
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
Current native TURN/TLS media still fails. A fresh September 14 chain check
against the pinned native roots also fails at ISRG Root X2. Adding that public
root to a temporary verifier input passes; neither the server chain nor the
native library was changed. The pinned
[Java certificate callback](https://github.com/webrtc-sdk/webrtc/blob/m144_release/sdk/android/api/org/webrtc/SSLCertificateVerifier.java)
accepts one DER certificate, and the current Flutter plugin does not install a verifier.
An unconditional callback or a TLS policy bypass is not a repair.

Prepare a compatible public certificate chain, or a reviewed native dependency
with the necessary public roots. Before staging a certificate, run the following
offline preflight with OpenSSL 3 and the retained, hashed root bundle from the
exact native library. `leaf.pem` and `chain.pem` must be the proposed public
certificate files; do not add the candidate chain to the trusted root input.

```sh
: "${TURN_TLS_CANDIDATE_DIR:?Set the prepared certificate directory}"
openssl verify -no-CApath -no-CAstore -purpose sslserver \
  -CAfile .codex-test-logs/call-fallback-priority2/remaining/pinned-native-certificates.pem \
  -untrusted "$TURN_TLS_CANDIDATE_DIR/chain.pem" \
  -verify_hostname mknoun.xyz "$TURN_TLS_CANDIDATE_DIR/leaf.pem"
openssl x509 -in "$TURN_TLS_CANDIDATE_DIR/leaf.pem" -checkend 2592000 -noout
```

The retained native root bundle SHA-256 is
`f698d5011d2f24fb4cb9fdbdf0d619325ba3751a5d97b8114d423158afadc28d`;
`turn-tls-current-preflight.json` retains the failed current-chain check and
isolated-root control. Re-establish the bundle's native-library provenance if
the dependency changes. Passing this preflight is followed by an isolated
coturn endpoint and the existing native TLS allocation/protected bidirectional
media matrix, including IPv4 preservation, before promoting certificate paths
under the active coturn unit. Save the current certificate/key paths and bytes;
rollback restores them and accounts for allocations lost on a coturn restart.
No certificate issuance, key replacement, coturn reload/restart or native
dependency upgrade was performed. Retain working TURN UDP/TCP alternatives
throughout.

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
