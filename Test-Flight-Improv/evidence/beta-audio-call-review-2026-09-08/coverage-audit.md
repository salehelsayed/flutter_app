# Coverage audit: what “all calls today” can establish

At 12:32 UTC on September 8, a read-only relay journal scan covered **Berlin midnight (September 7 22:00 UTC) through 12:32:19 UTC**. It returned 49,215 unit records, with entries in every calendar-hour bucket; the first was 22:00:13 and the last 12:32:14. This confirms broad retained operational-log coverage. It does **not** create a complete call-attempt history: the old call handler did not retain per-attempt outcomes, and the new selective logs omit routine successful activity.

The original Redis AOF export was filtered from **September 8 00:00 UTC onward**, not Berlin midnight, and was collected at 10:46 UTC. Its recoverable call metadata yielded **12 unique admitted handles / 23 directional mailboxes** from 10:10–10:17 UTC. It therefore did not reconstruct Berlin's first two hours. The later reported directional failure was investigated separately: one bidirectional handle survived around 11:03; the automatic AOF rewrite at 11:04:34 and short mailbox/replay lifetimes removed earlier detail. That surviving handle does not count both the failed forward attempt and successful reverse call as admitted calls.

Evidence distinctions:
- A client tap/attempt can fail before any mailbox commit; such attempts are not counted by admitted handles. One later lab tap also lacked a start postcondition, so it remains unclassified rather than being counted as a proven failed admitted call.
- A mailbox handle proves stored signaling existed. Direct signaling can bypass mailbox storage; encrypted event type and terminal reason are unavailable.
- APNs acceptance is not device delivery, ringing, answer, or media success. An ACK may acknowledge rejection, duplicates, or termination.
- TURN credential issuance is not allocation, selected ICE path, or connected audio.
- Actual accepted/connected states and bidirectional RTP were measured on the controlled final lab pair: three answered calls, including both directions and a retry after decline. They do not retroactively prove beta-device outcomes or human-perceived sound quality.

**Supported assurance:** we reviewed the recoverable beta-call evidence, found and fixed demonstrated defects, deployed server repairs, and verified the repaired app packages on the available lab pair. **Unsupported assurance:** every audio call today was individually reconstructed, every historical failure received an exact cause, or every possible bug has been found. Client fixes still need distribution to beta testers; server deployment does not update their apps.

No further calls, device actions, code edits, deployments, or tester messages occurred during this audit. See coverage-audit-journal.json for the sanitized retention summary, redis-call-timeline-summary.md and redis-followup-summary.md for recovered history, and physical-device-ui-native-answer-final.md for final media proof.
