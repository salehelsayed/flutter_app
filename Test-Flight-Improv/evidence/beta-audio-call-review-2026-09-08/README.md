> This is the initial incident snapshot. See [remediation and validation](remediation-validation.md) for the fixes deployed later on September 8 and the subsequent phone tests.

# Beta audio-call relay investigation — 2026-09-08

Investigation scope: production relay, retained call-control metadata, Prometheus history, live TURN probes, current call setup code, and accessible device diagnostics. The beta test time, participating devices, build versions, and exact successful call were not independently supplied by the testers. The relevant observed activity is September 8, approximately **10:10–10:18 UTC / 12:10–12:18 Europe/Berlin**.

## Recovered incident sequence

Redis's retained append-only history recovered **12 distinct call handles and 23 directional mailboxes across three peers**. Typed registrations identify one Android device (A = `peer-006`) and two iOS devices with production VoIP registrations (B = `peer-007`, C = `peer-008`). These are anonymous aliases, not verified tester names.

| First relay receipt, Berlin time | Initiating direction | Stored events, forward / reverse | Acknowledged, forward / reverse | Explicit mailbox cancellation |
|---|---|---:|---:|---|
| 12:10:00 | A → B | 1 / 1 | 1 / 1 | after 626 ms |
| 12:10:17 | A → B | 1 / 1 | 1 / 1 | after 514 ms |
| 12:10:26 | A → B | 1 / 1 | 1 / 1 | — |
| 12:11:36 | B → C | 6 / 6 | 6 / 6 | — |
| 12:12:01 | A → B | 1 / 1 | 1 / 1 | — |
| 12:12:06 | C → A | 4 / 8 | 4 / 7 | — |
| 12:12:36 | A → B | 1 / 1 | 1 / 1 | after 499 ms |
| 12:13:00 | A → B | 1 / 1 | 0 / 0 | — |
| 12:15:27 | A → B | 1 / 0 | 1 / 0 | — |
| 12:16:11 | A → B | 1 / 2 | 1 / 2 | — |
| 12:16:28 | A → B | 1 / 2 | 1 / 2 | — |
| 12:17:04 | A → B | 1 / 1 | 0 / 0 | after 471 ms |

**Ten observed attempts concentrate on the same Android → iPhone pair and have very little retained signaling. Four entered explicit terminal mailbox cleanup in under 700 ms.** The two richer exchanges align with the two bursts totaling four credential issuances. This supports investigating early call control/admission/termination for the repeated A → B failures. It does not support attributing all failures to TURN.

The iPhone → iPhone attempt at **12:11:36** is a candidate for the reported success, but **successful audio is not proved** by these records. The iPhone → Android attempt at **12:12:06** also exchanged substantially more signaling. Tester confirmation and client audio statistics would be needed to label either successful.

During the final attempts, B's typed call token and endpoint/device-route records were explicitly deleted in the bounded intervals **12:16:28.312–12:16:29.047** and **12:17:04.522–12:17:04.865**. A new token generation/refresh epoch appears between these groups. This was not ordinary expiry of the 30-day token or six-hour endpoint. The triggering client reason is not included in Redis metadata. These deletions do not explain the earlier rapid failures, which lacked the same deletion pattern.

Current source has a matching explicit teardown path: `_rollbackIosCallability(terminal: true)` disables native call capability, revokes the VoIP token, then revokes the endpoint (`production_call_signaling_graph.dart:913`). Shutdown/withdrawal, native lifecycle invalidation, token invalidation, or failed advertisement followed by withdrawal can reach it. **Ordinary iOS backgrounding does not revoke this graph** (`:522`). The records establish withdrawal/recovery, not which trigger fired. The stored token value did not change across the observed registrations, and the pairwise wake-grant identities remained unchanged during the window. Grant rotation and ordinary registration expiry are therefore not supported explanations for these observed mutations.

Interpretation limits: a mailbox ACK also covers permanently rejected, duplicate, or superseded signals. Signal kind and terminal reason are encrypted; random message IDs do not encode them. Every signal races direct and mailbox delivery, so mailbox counts need not include all directly delivered signaling. `mailbox.cancel` is also called by automatic terminal cleanup; it does not prove a human tapped Cancel. Calls that failed before the first mailbox store are absent from this reconstruction.

Evidence: [concise Redis reconstruction](redis-call-timeline-summary.md), [sanitized call timeline and registration history](redis-call-timeline.json). No encrypted envelope or user content was exported or interpreted.

## Confirmed deployment defects and separate source risks

**The relay is running, and its IPv4 TURN path works in the probes. Its advertised IPv6 TURN path is broken. The following source risks are additional verified mechanisms, not demonstrated causes of the 12 recovered attempts.**

1. **Advertised IPv6 TURN endpoint has no public listener.** `mknoun.xyz` resolves to both the relay's IPv4 and public IPv6 addresses. The app receives `turn:mknoun.xyz:3478?transport=udp` and the corresponding TCP URL. Coturn listens on the private IPv4 interface and loopback, including IPv6 loopback, but not the public IPv6 address. From the workspace network, IPv4 STUN binding succeeds over UDP and TCP; both IPv6 probes time out. A TCP connection to port 443 on the **same IPv6 address succeeds in 40 ms**, providing a positive IPv6 connectivity control. This is a production defect for clients relying on that IPv6 TURN endpoint. Whether a particular tester selected or required that endpoint is not recoverable from the server counters.

2. **No TURN TLS fallback is operating.** Coturn reports missing certificate/key files and cannot start its TLS/DTLS listeners. No `turns:` URL is advertised. Port 443 belongs to nginx, not a TURN listener. The available fallback is plain TCP 3478; a network blocking both UDP and TCP 3478 has no advertised working TURN TLS alternative. This is a verified deployment limitation, not evidence that the testers' networks blocked 3478.

3. **A recipient's advertised call endpoint expires after six hours.** `production_call_signaling_graph.dart:723` constructs a six-hour expiry. Publication runs on startup, resume, contact eligibility changes, and outgoing calls; no periodic renewal was found in the production composition. Starting a call refreshes the caller's advertisement. The caller still needs an unexpired recipient endpoint before sending the invite, so a push token alone cannot make an idle recipient callable. Redis enforces the endpoint expiry in `call_control_redis.go:1180` and `:1204`. At the snapshot, only **4 active endpoints** existed alongside **19 retained endpoint tombstones and 18 typed call tokens**. These are different entity counts across historical devices; they are not a denominator or proof that 15 beta testers were affected.

4. **Fresh/rotated contact grants can block the call before the invite.** Wake grants last 24 hours and rotate when less than 10 minutes 45 seconds remain (`call_wake_authorization_coordinator.dart:87`, `:246`). Outgoing startup refreshes authority and requires an exact durable recipient receipt for its grant before delegating the invite (`call_signaling_composition.dart:258`, `:280`). Production requires that receipt; failure returns before the contact-exchange offline mailbox fallback (`send_contact_request_use_case.dart:374`, `:414`). A sleeping recipient or incomplete exchange can therefore return unavailable before a call push. Existing contacts are backfilled automatically; recreating contacts is not required. A current, receipt-proven grant supports an offline recipient. These behaviors are source- and test-confirmed, but not individually attributed to beta attempts.

5. **Credential timeout budgets leave no room for slow relay failover.** Flutter waits five seconds for TURN credentials (`p2p_bridge_client.dart:200`); Go tries relays serially with a five-second per-relay probe budget (`go-mknoon/node/turn_credentials.go:109`, `node/config.go:35`). A stalled first relay can exhaust the app deadline before fallback returns. Production requires credentials even when direct ICE is permitted (`production_call_signaling_graph.dart:1308`, `:1377`). No evidence currently identifies this as the cause of a beta attempt.

## What the server proves

- Relay active since **2026-09-07 19:55:16 UTC**, with zero automatic restarts since startup. Coturn active since **2026-09-04 22:01:11 UTC**, also zero automatic restarts. Earlier relay deployments on September 7 are outside the observed morning burst.
- From a zero counter at 10:09 UTC, **13 APNs VoIP push submissions** were counted by 10:17:15 UTC. All recorded outcomes were `sent`; no APNs failure outcomes were nonzero. Provider acceptance does not prove device delivery, ringing, answer, or audio. A call may generate multiple pushes.
- **Four TURN credentials were issued**, first appearing as two at the 10:11:45 UTC scrape and four at 10:12:15 UTC. These are scrape observation times, not exact request timestamps. No other issuance outcome was present. Credential issuance does not establish allocation or audio, and it is not a count of successful calls.
- The old coturn hairpin allow rule for the relay's private IPv4 address is present. The issuer's primary secret matches coturn's configured secret; no secret values were recorded.
- Fresh, short-lived diagnostic credentials successfully allocated and exchanged **10/10 packets over UDP and 10/10 over TCP**, with zero loss, using coturn's client-to-client test mode. This probe ran on the relay against its public IPv4 address. It proves that allocation and the server-side IPv4 hairpin work; it does not exercise a tester's carrier or audio device. The test mode is documented by [coturn](https://github.com/coturn/coturn/wiki/turnutils_uclient).

Evidence: [relay snapshot and Prometheus series](relay-snapshot.json), [network probes with IPv6 control](network-probes.json), [TURN listeners](turn-listeners.txt), [authenticated TURN probes](turn-authenticated-probes.json).

## Diagnostic limits

The call-control handler returns structured errors to clients but does not retain per-attempt action/outcome logs. Call mailbox payloads are bounded to 45 seconds; replay tombstones last 10 minutes (`call_control.go:32–34`). No mailbox keys remained at the first Redis snapshot. Retained append-only history supplied the sequence above, but cannot reveal encrypted signal kinds or terminal reasons.

Prometheus scrapes the relay, Redis, and node exporter, but not coturn allocation/media counters. Coturn's retained normal log does not provide a selected ICE pair or an audio outcome. Journal inspection for September 7–8 found call-related startup flags, not per-call failure reasons.

The USB Pixel's app log buffer starts at **10:27:57 UTC**, after the observed call burst. It contains no retained call-start, endpoint, grant, TURN, or WebRTC events. Read-only application diagnostic filename searches found no accessible persisted log files within the inspected directories. No databases or chat content were read. Later node readiness success does not establish earlier call success.

Both discovered physical iPhones allowed app/shared-container and crash-inventory inspection. Neither had an accessible persisted diagnostic trace for the window or a listed September 8 Runner/Mknoon crash. Their participation in the beta calls is unconfirmed. No apps were launched or terminated, and no database, token, contact, or media contents were copied.

## Validation

Passed **74 focused Flutter tests** with the installed Flutter 3.47.2 SDK:

```sh
/Users/I560101/development/flutter-3.47.2/bin/flutter test \
  test/features/call/application/call_wake_authorization_coordinator_test.dart \
  test/core/bootstrap/call_wake_contact_key_backfill_test.dart \
  test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart \
  --reporter expanded
```

Passed the focused relay and Go-node credential tests:

```sh
# go-relay-server/
go test . -run '^TestTurnCredentialsV1_' -count=1
# go-mknoon/
go test ./node -run '^TestTurnCredentialsV1_|^TestTurnCredentialLeaseManager_' -count=1
```

These validate credential contracts and the grant readiness behaviors. They do not prove beta-device audio. The signaling integration test's injected connected state is also not an audio oracle.

## Repair priorities

1. Capture the first terminal reason on the affected Android/iOS pair: endpoint resolution, incoming admission/presentation, native call actions, and capability revocation. Match the timestamp to the reconstructed attempts. Include both phone build versions and whether the receiver rang or answered. This is necessary to identify the repeated pair-specific failure conclusively.
2. Make the advertised TURN addresses usable: bind and expose the public IPv6 listener, verify authenticated IPv6 allocation and packet forwarding from an external client, and provide a tested TURN TLS fallback for restricted networks.
3. Remove dependence on a recipient foregrounding within six hours while preserving signed endpoint validity, device epochs, and revocation. Account for idle recipient wake-up and expired-grant recovery explicitly. Ensure grant replacement has a durable delivery/recovery path; preserve exact receipt and authorization checks.
4. Give relay failover a shared deadline that fits inside the client deadline, and add bounded call-control outcome metrics plus client start/admission/ICE failure diagnostics. Keep identifiers, tokens, credentials, SDP, and candidates out of metrics.

This initial review was captured before remediation. At that stage, no application source, production configuration, or running service had changed. Subsequent authorized fixes, deployments, and validation are recorded in [remediation-validation.md](remediation-validation.md). Diagnostic traffic and automated calls use lab endpoints; no calls or messages were sent to beta testers.
