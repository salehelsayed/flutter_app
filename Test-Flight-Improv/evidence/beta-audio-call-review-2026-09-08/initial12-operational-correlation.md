# Operational correlation for each initial call

Window: September 8, 2026 **10:09–10:19 UTC**. This correlates the original 12 stored handles with retained provider/credential metrics and operational logs. It does not decode signaling or infer audio outcome from ACKs.

| Handle | First store UTC | APNs sent change in overlapping 15s observation bucket | TURN issuance observation | Attribution |
| --- | --- | --- | --- | --- |
| call-090 | 10:10:00.044 | +1 at 10:10:15 | No issued series yet | Only this handle starts in bucket; still unbound |
| call-091 | 10:10:17.386 | +2 at 10:10:30 | No issued series yet | Shared with call-092 |
| call-092 | 10:10:26.992 | +2 at 10:10:30 | No issued series yet | Shared with call-091 |
| call-093 | 10:11:36.513 | +2 at 10:11:45 | First observed cumulative 2 | Only this handle starts in bucket; still unbound |
| call-094 | 10:12:01.789 | +2 at 10:12:15 | +2; cumulative 4 | Shared with call-095 |
| call-095 | 10:12:06.055 | +2 at 10:12:15 | +2; cumulative 4 | Shared with call-094 |
| call-096 | 10:12:36.516 | +1 at 10:12:45 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |
| call-097 | 10:13:00.169 | +1 at 10:13:15 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |
| call-098 | 10:15:27.340 | +1 at 10:15:30 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |
| call-099 | 10:16:11.240 | +1 at 10:16:15 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |
| call-100 | 10:16:28.312 | +1 at 10:16:30 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |
| call-101 | 10:17:04.394 | +1 at 10:17:15 | +0; cumulative 4 | Only this handle starts in bucket; still unbound |

The metric intervals are nominal query observation windows. A range query selects preceding scrape values, so these are not exact request-time bounds. Each series lacks a handle or peer label: even a bucket containing only one new handle cannot prove that its push count belongs to that handle. Existing signaling, reciprocal events, retries, and other attempts are possible. The two +2 APNs buckets containing call-091/call-092 and call-094/call-095 are explicitly ambiguous.

## Findings shared across the twelve calls

- APNs sent increased from 0 to 13. Every recorded non-sent outcome stayed 0 for all 41 samples: auth_error, canceled, expired, invalid_token, network, provider_error, rate_limited, rejected_payload, rejected_route, sent_cross_environment, and server_error. This weighs against a recorded APNs provider-submission/auth rejection as the common failure. It does not show device delivery, ringing, user answer, or successful audio.
- TURN issuance first appears at cumulative 2 in the 10:11:45 observation and reaches 4 at 10:12:15. The unfiltered all-outcomes query returns only the issued series; no error-outcome series is retained, and no explicit zero baseline exists for those absent series. Thus no issuer error is observed, but failed or pre-request attempts are not excluded. The 10:11:45 observation lies within call-093 traffic 10:11:36.513–10:11:58.419; the 10:12:15 observation lies within call-095 traffic 10:12:06.055–10:12:21.939. This is temporal association with the two richer exchanges, not unique credential assignment or proof of allocation, ICE, or RTP. No fresh issuance increment is seen around the later short/zero-ACK attempts. Cached credentials, pre-request exits, and unrecorded allocation failures remain possible.
- No retained relay FCM/wake metric series matched the bounded historical query. This is an observability limit, not evidence that Android wake did not occur. Completed Redis wakeClaims can result from ACK handling and were not treated as provider submissions.
- Relay, Redis, and node up=1 at all 41 samples. The initial 10:38 snapshot recorded relay active since Sep 7 19:55:16 and coturn since Sep 4 22:01:11, both with NRestarts=0. Thus a service restart is not supported for any of the twelve calls. Sampled up does not exclude a brief stall or a client-specific network failure.
- The relay journal contains 12,258 records for the window, all priority 6, without matched service-lifecycle, panic/process-fault, structured call-action, APNs/VoIP, or TURN-credential entries. A separate fixed error-keyword scan found no error/failed/timeout/authorization/connection-error matches. Old handler errors were returned to clients without per-attempt logging, so this cannot establish that requests succeeded.
- Coturn journal has no entries in the window. The retained Sep8 file has 79 lines: one old-process midnight log-open record, then the later 11:09 repair startup and an 11:24:44 socket-error record outside the incident. No incident allocation, usage, or session-error records can be recovered. Quiet logging does not rule out TURN authentication, allocation, transport, or ICE failure.

## Hypothesis bounds for the requested failure times

For call-090 (10:10:00), call-091 (10:10:17), and call-096 (10:12:36), the overlapping APNs counter increments coexist with the separately recovered sub-700 ms mailbox cancellation. This supports that provider submissions occurred in those periods; it cannot determine whether the cancellation preceded dispatch or was caused by preflight, a remote rejection, UI, native lifecycle, or another encrypted reason.

For call-097 (10:13:00) and call-101 (10:17:04), provider accepted submissions overlap the periods with zero mailbox ACKs. These facts can coexist: provider acceptance is not recipient custody or application delivery. Device receipt/suppression, app admission, and caller cancellation remain indistinguishable from these aggregates.

For call-098 (10:15:27), call-100 (10:16:28), and call-101 (10:17:04), there is no observed new TURN issuance; the APNs sent counter increases in each corresponding observation period. Explicit authority deletions at the final two times are evaluated in the separate per-call registration timeline. No service outage or provider rejection is recorded at those times.

The previously confirmed absent public IPv6 TURN listener and missing TURN TLS listener are deployment defects, now repaired. There is no selected address family/transport for any of these twelve handles, so neither defect can be named as the proven cause of an individual failure. The pre-repair matching issuer/coturn secret and successful IPv4 diagnostic allocation weigh against a blanket broken IPv4 authentication deployment, but do not exclude a session-specific credential or carrier issue.

No historical call is labeled audio-successful by this correlation. Read-only collection only: no new calls, phone actions, service mutations, code changes, or tester messages. Files: initial12-operational-correlation.json, initial12-operational-window.json, initial12-turn-log-coverage.json, initial12-relay-error-keywords.json.
