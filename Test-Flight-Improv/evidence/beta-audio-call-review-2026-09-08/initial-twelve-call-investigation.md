# Individual investigation of the first twelve beta calls

Investigated September 8, 2026, using the retained relay evidence. **All twelve handles were examined individually. All twelve reached relay storage; the exact encrypted reason and audio outcome of each call cannot be recovered.** The earlier burst therefore cannot be explained wholesale by the same pre-admission failure inferred for the later Android → private iPhone attempt.

The strongest findings are four rapid, explicit cancellations; one acknowledged envelope with no stored reciprocal event; two exchanges without mailbox acknowledgements; and explicit removal of the same iPhone's call registration interleaved with the last three attempts. Two richer exchanges coincide with the only observed TURN credential issuance increments. These findings narrow the failure paths without turning timing correlations into proven client errors.

## Evidence and identities

The original, preserved incremental-AOF export contains **12 handles, 23 directional mailboxes, 45 stored envelopes, and 40 acknowledged envelopes**, from **10:10:00.044 to 10:17:04.865 UTC**. That is **12:10–12:17 Berlin time**. Aliases below are the original export's stable aliases:

- **A:** `peer-006`, Android.
- **B:** `peer-007`, iPhone using production VoIP registration.
- **C:** `peer-008`, another iPhone using production VoIP registration.

These are device aliases, not independently verified tester names. B also appears in the later directional incident, whose Android participant was a different device. Direction means the **first stored envelope**; the relay export alone does not prove which person tapped Call.

The raw source is [redis-call-timeline.json](redis-call-timeline.json). A separate, hash-bound derivation records every envelope's receipt time, remaining lifetime, acknowledgement count, and cancellation in [initial-twelve-call-facts.json](initial-twelve-call-facts.json). The original export is unchanged.

The backed-up historical relay binary's SHA-256 matches the original snapshot. Its embedded revision is `298934482b0a30960dee47dd1adfd5c4d8e4f40d`; all eight audited mailbox/wake source and test files are byte-identical between that tracked revision, the later baseline, and the reviewed working tree. The binary also reports `vcs.modified=true`, so unknown build-time edits cannot be excluded. Source-based interpretations below are supported by the matching tracked code and stored record patterns, with that provenance limit retained in [historical-relay-binary-provenance.json](historical-relay-binary-provenance.json) and the semantics audit.

## Per-call findings

All times in this table are UTC. Add two hours for Berlin. Acknowledgement counts describe release of relay custody, not answered calls. Signal spans are not call durations.

| Call | First store / direction | What the relay proves | Diagnosis supported by this evidence |
| --- | --- | --- | --- |
| **090** | 10:10:00.044, A → B | One envelope each way, both acknowledged. B's envelope arrived **213 ms** after A's. A's outgoing mailbox was explicitly canceled at **+626 ms**. | A rapid cancellation followed a reciprocal exchange. This was not a missing initial mailbox or natural envelope expiry. A remote rejection, local abort, or lifecycle failure cannot be distinguished from the encrypted records; ringing is unproven. |
| **091** | 10:10:17.386, A → B | One envelope each way, both acknowledged. B replied at **+252 ms**; A's mailbox was explicitly canceled at **+514 ms**. | Same rapid-cancellation pattern as 090. B emitted authenticated reciprocal traffic, so complete silence from B does not explain the record. The cancellation's client reason is unavailable. |
| **092** | 10:10:26.992, A → B | One acknowledged envelope each way. B's stored reply arrived **18.566 seconds** later. No explicit canceled tombstone was exported. | A delayed reciprocal response, unlike the subsecond failures. An answer, decline, timeout-related signal, or other control response cannot be identified from its encrypted content. Absence of a canceled tombstone does not establish connection. |
| **093** | 10:11:36.513, B → C | Six envelopes in each direction, all twelve acknowledged. Recorded traffic spans **21.906 seconds**. The first cumulative **two TURN credentials** appear in the 10:11:45 observation. | A strong candidate for reaching media negotiation. It could be the reported successful call, but neither the mailbox nor the unbound TURN counter proves that identity or audio success. |
| **094** | 10:12:01.789, A → B | One envelope each way, both acknowledged. B's reply arrived **849 ms** later. No explicit cancellation was exported. | A short reciprocal exchange with unknown meaning. It shares the next provider/credential observation bucket with 095, so that bucket cannot be assigned to 094 or 095 uniquely. |
| **095** | 10:12:06.055, C → A | Four C → A envelopes, all acknowledged; eight A → C envelopes, seven acknowledged. The first seven A → C envelopes were drained before an eighth was stored at **10:12:21.939**, with no retained ACK afterward. Traffic spans **15.884 seconds**. Two more TURN credentials appear in the 10:12:15 observation. | Another strong candidate for reaching media negotiation. The final unacknowledged envelope is not proof of lost audio: its type is unknown, direct delivery is possible, and a terminal signal may outlive mailbox polling. No retained ICE/RTP record establishes success or failure. |
| **096** | 10:12:36.516, A → B | One acknowledged envelope each way. B replied at **+203 ms**; A's mailbox was explicitly canceled at **+499 ms**. | Same early-cancellation pattern as 090/091. No contemporaneous B registration deletion was found. A later registration withdrawal cannot explain this earlier attempt. |
| **097** | 10:13:00.169, A → B | One envelope each way; **neither was acknowledged**. B nevertheless emitted its reciprocal envelope at **+1.503 seconds**. No explicit cancellation was exported. | Mailbox custody was not released, but B was not entirely silent. Direct receipt, rejection, interrupted processing, and missing/failed acknowledgement remain possible. Zero ACKs alone cannot mean that neither phone received signaling. |
| **098** | 10:15:27.340, A → B | A's sole stored envelope was acknowledged. **No reciprocal mailbox** was retained. B had previously recorded unexpired endpoint/token/wake authority, with no deletion before this receipt. | This narrows the observation to an acknowledged envelope without a stored B response. It does not show a missing initial relay admission. Discard, suppression, no response, and direct-only response remain indistinguishable. |
| **099** | 10:16:11.240, A → B | A stored one envelope; B stored two, all acknowledged. B's first reply arrived at **+374 ms**; its second at **10:16:29.047**. Call 100 had already begun **735 ms** before that second reply. B's first registration removal falls inside this interleaving. | A registration/lifecycle interruption is a concrete lead for this exchange. The record does not show whether 099 was still ringing or active when 100 began, or what either B reply meant. |
| **100** | 10:16:28.312, A → B | A stored one envelope; B stored two, all acknowledged, at **+1.087 s** and **+6.395 s**. B's token, endpoint, and endpoint-device removals occur after this first store and before 099's final envelope at **10:16:29.047**. | The initial A → B store succeeded, then B's call registration was explicitly removed during the overlapping traffic. This is stronger evidence for a lifecycle/authority interruption than for TTL expiry or a relay outage. The originating client callback remains unknown. |
| **101** | 10:17:04.394, A → B | B's reciprocal envelope arrived at **+128 ms**. Neither direction was acknowledged. B's second registration removal is bounded between **10:17:04.522 and 10:17:04.865**. A's mailbox was explicitly canceled at the latter time, **+471 ms**. | The clearest temporal combination of registration withdrawal, unacknowledged signaling, and rapid cancellation. It proves the interruption occurred, but cannot identify the encrypted rejection or establish which client event initiated the sequence. |

The four explicit cancellations occurred while their first envelopes still had about forty seconds of lifetime. The `canceled` state comes from the sender cancellation path, not ordinary expiry. It identifies the request's authenticated sender, not whether a person tapped Cancel: automatic cleanup also uses that operation.

## The registration interruption in detail

Prior records for every first recipient show future recorded expiry for the endpoint, typed push token, and relevant wake authorization. Recorded expiry alone does not independently establish the Redis key's TTL or the caller's locally held grant/receipt state. The export contains no token identity-change flag set to true for A/B/C during these calls. Observed endpoint publications advance their preference epochs and retain their device-key epochs. **Ordinary authority expiry is not supported as the cause of these twelve initial admissions.** The previously fixed publication race is also not directly demonstrated by a backward epoch write in this AOF record; successful writes cannot establish or exclude rejected publication attempts.

Two B deletion episodes are concrete:

1. **After 10:16:28.312, before 10:16:29.047:** token, endpoint, and endpoint-device removal occurs between call 100's first envelope and call 099's final envelope. It must not be attributed only to 100 or described as a clean boundary between calls.
2. **After 10:17:04.522, before 10:17:04.865:** the same removal pattern occurs after call 101's reciprocal envelope and before its recorded cancellation.

The endpoint deletion plus endpoint-device deletion and endpoint-tombstone writes match explicit `RevokeEndpoint` behavior, which performs those endpoint operations in one Redis transaction. Redis TTL expiration does not produce that application tombstone sequence. Token deletion is a separate operation, consistent with application lifecycle withdrawal; adjacency does not prove that it was atomic with the endpoint revocation or name the client callback. Registration mutation times are **AOF command-order bounds**, not exact receipt timestamps.

Those removals cannot retroactively explain calls 090–098. Re-registration between the two episodes does not itself prove recovery of native CallKit, incoming admission, or media. The detailed state reconstruction, with 184 validated source pointers across all 23 directional mailboxes, is in [registration-authority-analysis.md](registration-authority-analysis.md).

## What the operational records rule out, and what they do not

- **No recorded common service outage:** relay, Redis, and node reported up in all 41 samples across 10:09–10:19; no restart evidence was found. A brief stall or an individual device's network failure remains possible.
- **No recorded APNs provider rejection:** the sent counter rose from zero to thirteen, while all recorded failure outcomes stayed zero. Provider acceptance is not device delivery, ringing, or answer. Fifteen-second observations have no call binding; reciprocal traffic and retries can share a bucket.
- **Only four observed TURN credentials issued:** the increments align in time with the richer 093 and 095 exchanges. No issuer-error series was retained. This does not prove that all other attempts failed before a credential request or that these four credentials yielded an allocation or media connection.
- **No recoverable incident TURN session trace:** coturn retained no allocation, selected-transport, ICE, or RTP record for these twelve calls. The confirmed IPv6/TLS listener defects cannot therefore be assigned as the proven cause of a particular historical call.

See [per-call operational correlation](initial12-operational-correlation.md) for every handle's observation bucket and the retained log coverage.

## Correct interpretation of ACK and wake records

Several tempting conclusions are not supported by this data:

- A stored envelope proves relay admission/custody for that envelope, not that the phone displayed it.
- Acknowledgement releases relay custody. It can accompany rejection, duplicate handling, or termination and does not prove user acceptance.
- `wakeClaims: completed` can be written by ACK, by attached-iOS suppression, or after a wake dispatch attempt succeeds, fails, or is skipped. Even a full claimed/dispatching/completed sequence is not proof that a provider accepted a push. Duplicate writes are not push counts.
- The client starts direct and mailbox delivery together. Direct acceptance can complete delivery while mailbox storage remains unsettled or fails. Sparse mailbox traffic and missing ACKs cannot exclude direct-path signaling or media.
- Visible envelope expiration is not an event-type discriminator. The relay does not decrypt the event to choose that deadline, and mailbox expiration retains the maximum accepted deadline even after some envelopes are acknowledged.
- The original export did not preserve per-retrieval or ACK receipt timestamps. The original AOF was automatically rewritten at 11:04:34, so those omitted timings cannot now be recovered from that file.

See [mailbox semantics audit](initial-twelve-mailbox-semantics.md) for source/test anchors and baseline verification. Direct/mailbox racing was separately checked in unchanged `call_signaling_service.dart`, including the exact test `direct acceptance exposes exact mailbox settlement before retirement`.

## Relationship to the repairs already made

This follow-up does **not** establish that every earlier call had the same bug as the later Android → private iPhone attempt.

- Cached “unavailable” state and short reachability lifetimes do not explain why an already stored initial envelope failed to become an answered call. Their fixes address demonstrated client defects and future attempts; the earlier twelve do not prove those defects caused their outcomes.
- The late B registration removals make publication/invalidation and graph ownership relevant to 099–101. The serialized publication and stale-graph readiness fixes address demonstrated races, but the historical export does not identify their exact triggering code path.
- TURN listener repairs and the credential deadline fix address independently demonstrated defects. They are plausible concerns for the media-stage candidates, with no per-call transport proof for attribution.
- Android full-screen permission and notification improvements concern Android incoming presentation, principally the C → A direction here. They cannot explain the ten A → B attempts where the recipient was an iPhone. The foreground native Answer bug was reproduced during our later QA and repaired; it is not established as a beta-burst cause.

No additional production change was made solely from these correlations. Existing fixes remain validated by regression tests and final physical calls in both directions. Establishing the exact historical client error would require the corresponding retained endpoint diagnostics; relay ciphertext, expired records, and aggregate counters cannot supply it retrospectively.
