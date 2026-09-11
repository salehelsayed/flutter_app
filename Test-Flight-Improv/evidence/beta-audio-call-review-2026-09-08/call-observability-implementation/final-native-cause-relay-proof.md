# Final native-cause probe: relay evidence

One bounded, read-only capture at **2026-09-08 16:51:53 UTC**. Companion JSON: `final-native-cause-relay-proof.json`. Exact caller trace: `5879d7e3-35a3-49b7-9bcb-4760b9d124c3`. The device QA owner identifies this as the final source `f1899f0d63e1724b` iOS-to-Android probe.

## Result

The relay accepted and committed the mailbox traffic, invoked the Android push provider successfully, and recorded the caller's `no_answer` terminal. This is an unsuccessful call with confirmed relay custody/provider submission. The snapshot does not contain Android admission, callee terminal, answer or media evidence, so it cannot independently explain the Android deferral.

| Event | Occurred at UTC | Relay diagnostic receipt UTC |
| --- | --- | --- |
| First mailbox commit, `storeCommitted=true` | 16:49:06.542 | 16:49:06.559 |
| First Android provider invocation | 16:49:06.544 | 16:49:06.569 |
| First provider success | 16:49:06.637 | 16:49:06.637 |
| First response written | 16:49:06.637 | 16:49:06.666 |
| Flutter caller terminal `no_answer` | 16:49:36.374 | 16:49:36.635 |
| iOS native terminal, reason `unknown` | 16:49:36.405 | 16:49:40.122 |
| Second mailbox commit, `storeCommitted=true` | 16:49:36.568 | 16:49:36.585 |
| Second Android provider invocation | 16:49:36.570 | 16:49:36.596 |
| Second provider success | 16:49:36.639 | 16:49:36.645 |
| Second response written | 16:49:36.640 | 16:49:36.711 |

There are 84 retained records: 38 relay/server, 41 Flutter/caller and 5 iOS/caller. The trace has zero rejected/unreadable records, zero recorded distinct drops and no historical quota-loss counter. No ACK or TURN-stage records occur in this projection. Neither endpoint reports verified media; only the caller terminal is present.

`presentationReported=true` comes from iOS **caller** native presentation events; it does not prove that the Android callee rang. The first relay-received failed phase is the Flutter direct-send `transport_failed`. The successful mailbox/provider path prevents treating that direct-path failure alone as the cause of the no-answer result. One operation reference remains unresolved. Encrypted mailbox event types are not inferred from the two commits.

## Android evidence is still local

The separate provisional trace `0e714018-ba56-4aa6-8b8c-863af7c896e4` has no persisted trace record at this capture. The joined caller projection also contains no Android records.

The device QA owner separately reports admission after 949 ms with disposition `deferred`, cause `bridge_unavailable`, then `pending` finish after 981 ms; the second wake has the same cause. Android has 209 queued events and zero drops; iOS has zero queued events and zero drops. These are explicitly attributed device observations, not server-received evidence or a completed automatic join. Missing server evidence does not prove the local records were lost. The iOS native terminal now says `unknown`, while Flutter supplies `no_answer`; no local-user origin is invented.

Event-reported builds are preserved as received: Flutter caller `1.0.1+111-8bc9c8a8e32d3a38`, iOS native `1.0.1+111`, relay `7c70c5616c335ee1a3435730a153946466b73b636a138a1fef3ae78732900865`. Installed-source provenance belongs to the device owner's build manifest, rather than being inferred from these differently scoped fields.

## Relay health and aggregate limits

At the snapshot, diagnostics storage readiness is 1; accepted events are 122 and rejection, quota-exceeded, queue-full and sink-unavailable counters are all zero. These are current-process counters, not full-day totals. Relay, coturn and Prometheus are active/running with `NRestarts=0`. The monitor timer is active/waiting; its one-shot service is inactive/dead when sampled. Relay active-since is 16:19:10 UTC.

The bounded three-hour overview contains 10 retained traces, 8 with mailbox admission and zero invalid/unreadable records. One trace has any-endpoint media evidence, zero have both-endpoint media or both-endpoint terminals. These trace counts include provisional/partial records and are not a count of distinct call attempts. Modern distinct drops are zero; the earlier quota incident retains 1,062 legacy refusal attempts, including retries, with unknown unique historical loss. An empty alert list does not establish successful calls or complete endpoint coverage.

The export contains only strict operator projections, fixed metric/service fields and attributed bounded device facts. A recursive forbidden-field check found zero raw authority/credential/payload keys. No private author maps, phone logs, identities, raw handles, IPs or credentials were exported. This capture performed no code changes, calls, deployments or service mutations.
