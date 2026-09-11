# Redis call mailbox reconstruction — 2026-09-08

The production incremental Redis AOF was parsed on the relay in place. The base snapshot was last rewritten on September 5; the incremental file retains the September 8 window. Only allowlisted metadata and per-run aliases were exported. No envelopes, tokens, account/device IDs, raw handles, or raw AOF were exported.

Observed **12 unique call handles**, **23 directional mailboxes**, and **3 peers**, from 10:10:00 through 10:17:04 UTC.

- peer-006: android
- peer-007: ios production VoIP
- peer-008: ios production VoIP

| Handle | First receipt UTC | Pair | Stored / ACKed events by direction | Notes |
|---|---|---|---|---|
| call-090 | 10:10:00.044 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 1/1 | peer-006 canceled at +0.626s |
| call-091 | 10:10:17.386 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 1/1 | peer-006 canceled at +0.514s |
| call-092 | 10:10:26.992 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 1/1 |  |
| call-093 | 10:11:36.513 | peer-007↔peer-008 | peer-007→peer-008: 6/6; peer-008→peer-007: 6/6 |  |
| call-094 | 10:12:01.789 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 1/1 |  |
| call-095 | 10:12:06.055 | peer-008↔peer-006 | peer-008→peer-006: 4/4; peer-006→peer-008: 8/7 |  |
| call-096 | 10:12:36.516 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 1/1 | peer-006 canceled at +0.499s |
| call-097 | 10:13:00.169 | peer-006↔peer-007 | peer-006→peer-007: 1/0; peer-007→peer-006: 1/0 | No events acknowledged |
| call-098 | 10:15:27.340 | peer-006↔peer-007 | peer-006→peer-007: 1/1 | No reciprocal mailbox observed |
| call-099 | 10:16:11.240 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 2/2 |  |
| call-100 | 10:16:28.312 | peer-006↔peer-007 | peer-006→peer-007: 1/1; peer-007→peer-006: 2/2 |  |
| call-101 | 10:17:04.394 | peer-006↔peer-007 | peer-006→peer-007: 1/0; peer-007→peer-006: 1/0 | peer-006 canceled at +0.471s; No events acknowledged |

The ten Android↔peer-007 iOS handles exchanged at most one event in the initial direction and at most two events in the reciprocal direction. The two richer exchanges were peer-007 iOS↔peer-008 iOS at 10:11:36 (6+6 events, all acknowledged), and peer-008 iOS↔Android at 10:12:06 (4+8 events, 4+7 acknowledged). These are signaling observations; encrypted event types and audio outcome are unknown.

Two peer-007 iOS registration deletion groups occurred during the observed window:

- Between 10:16:28.312 and 10:16:29.047 UTC: token, endpoint, and endpoint-device deleted.
- Between 10:17:04.522 and 10:17:04.865 UTC: token, endpoint, and endpoint-device deleted.

The deleted registrations had future expirations (token about 30 days, endpoint about 6 hours), so those command sequences are not explained by their ordinary TTL expiry. A new peer-007 token registration appeared between the two groups with refreshEpoch=5/generation=3, compared with refreshEpoch=3/generation=2 before the first group. The allowlisted token comparison showed no token-byte changes across observed registrations; this distinguishes token lifecycle churn from a token-string change. The AOF does not contain the trigger/reason for deletion.

No same registration deletion group occurred around the earlier <700ms cancellations at 10:10:00, 10:10:17, or 10:12:36. Repeated wake grant registrations among these three peers did not change their stored grant identity during the call window. Endpoint routing-handle changes did occur during the session; timestamps in the JSON are command-order bounds, not exact endpoint registration receipt times.

Limits:

- ACK means that the recipient acknowledged encrypted signaling. It can include a rejection or termination; it does not establish user acceptance, ICE, audio, or media success.
- A pending tombstone with zero pending events is normal until TTL; it is not an active-call verdict.
- The `canceled` tombstones distinguish sender cancellation from a natural timeout in current `redisCallControlStore.Cancel` / `terminalizeTx` source. Their client reason is encrypted/unavailable in the AOF.
- No receipt timestamp is stored on endpoint/token/grant mutations. Bounds use adjacent observed call-event/terminal timestamps in AOF command order.
- This capture includes observed stored mailboxes; attempts rejected before a Store commit would not appear.

Detailed evidence: `redis-call-timeline.json`.
