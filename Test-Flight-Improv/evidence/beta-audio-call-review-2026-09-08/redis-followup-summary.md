# Fresh directional-call report — captured September 8, 2026

The user reported a new attempt: an Android beta tester received an error calling the user's private iPhone; the reverse iPhone→Android call worked. The coordinating task placed this activity approximately around 11:01–11:03 UTC. This report does not substitute inferred outcomes for that user observation.

## Evidence retained

- At the first available 11:06:30 UTC incremental-AOF capture, Redis had already automatically rewritten its AOF at **11:04:34 UTC**. The old sequence 29 incremental file was removed and no deleted open descriptor remained. Sequence 30 contained 93 commands and no call mailbox commands. Therefore its empty call list is not evidence that calls were absent before the rewrite.
- A separate authenticated, read-only Redis scan completed at **11:08:37 UTC**, while call tombstones remained live. It found exactly **one unique call handle** with two reciprocal `pending` tombstones and two replay directories. The recipients were prior **peer-007 (iOS production VoIP)** and **followup-peer-005 (a different Android device from earlier peer-006)**. Both aliases use allowlisted metadata; raw identities and handles were not exported.
- Those tombstones record final payload expirations **11:03:53.481 UTC** and **11:03:53.754 UTC**. They have no cancellation state or terminal timestamp. Their remaining Redis TTL was approximately 315 seconds when captured.
- Prometheus first shows **APNs sent 13→14** and **TURN credentials issued 4→6** in the **11:03:15 UTC** scrape. All fixed APNs failure counters remained zero across the 10:59–11:09 query window.
- Redis reported **evicted_keys=0**, with `allkeys-lru` and a 100 MiB maxmemory setting. Memory eviction does not explain a missing extra tombstone in this capture.

## Directional inference and its limits

Given the reported 11:01–11:03 timing, a separate forward attempt admitted to the call mailbox should normally still have a ten-minute replay tombstone at 11:08:37. The current store, cancel, endpoint-revoke and token-revoke implementations preserve that replay-tombstone boundary; endpoint/token revocation does not erase mailbox tombstones. Only one handle was observed live. This supports a forward failure **before a distinct mailbox admission**, conditional on the incident timing and ordinary production cleanup behavior. It does not prove the failed request's exact error code or identify which client preflight failed.

The successful reverse exchange is consistent with the one surviving bidirectional handle and two new TURN credentials, but the encrypted payload types, ACK counts, media phases, and order of initial caller direction were lost from retained mailbox metadata before capture. The user's report supplies the audio outcome; server metadata alone does not prove audio success.

## Authority state

Peer-007's current iOS endpoint preference epoch corresponds to **11:03:06.848 UTC**. Its current VoIP token has **refreshEpoch=7, generation=5**, compared with refreshEpoch=5/generation=3 after the earlier 10:16 deletion/re-registration. The current endpoint exists and expires six hours after its latest epoch. The fresh Android endpoint epoch corresponds to **11:04:13.654 UTC**.

Earlier retained evidence proved peer-007 token+endpoint deletions at 10:16:28–29 and 10:17:04. The post-rewrite snapshot cannot show exactly when later generations were published or whether the endpoint was absent immediately before the fresh forward failure. That hypothesis needs device diagnostics or previously retained journal evidence.

Artifacts:

- `redis-call-timeline-followup.json`: incremental AOF capture after rewrite; explicitly incomplete for the incident history.
- `redis-live-followup.json`: live typed records, tombstones and TTLs captured before expiry.
- `prometheus-followup.json`: fixed-outcome APNs/TURN series over the fresh window.

No production state was changed while collecting this evidence. Credentials were used only inside the relay process environment and were never exported.
