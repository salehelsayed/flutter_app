# Private Group Chat Reliability Test Matrix Row Breakdown

Status: decomposition-ready

Source matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`

Target breakdown: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`

## Decomposition Progress

| Timestamp | Phase | Rows or files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 19:29:18 CEST | Evidence Map started | Located bridge files, group application files, DB helpers, integration harnesses, Go tests, and Flutter tests relevant to the matrix. | No implementation or tests will be executed; evidence mapping is inspection-only. | Map likely entry files, existing nearby tests, missing tests, and named gates per row. |
| 2026-05-10 19:33:40 CEST | Evidence Map completed | Inspected source matrix, test-inventory, bridge/native files, group application surfaces, DB helpers, integration harnesses, and Go group tests. | No exact private-matrix row-id closure was found; nearby evidence is mapped as supporting context only. | Assign row dispositions without marking unproven rows covered. |
| 2026-05-10 19:33:46 CEST | Row Disposition started | Current status counts: 171 Open, 31 Partial, 0 Covered, 0 Unsupported. | Use source status plus current repo evidence: Partial -> tests-only; Open -> code-and-tests unless a later row plan proves otherwise. | Produce pipeline-compatible session classifications. |
| 2026-05-10 19:34:12 CEST | Row Disposition completed | All 202 rows assigned row-level dispositions and pipeline session classifications. | 171 rows needs_code_and_tests; 31 rows needs_tests_only; no rows marked covered_in_repo. | Run dependency pass and order sessions P0 -> P1 -> P2. |
| 2026-05-10 19:34:20 CEST | Dependency Pass started | Reviewed rows for shared prerequisites, duplicates, and ordering constraints. | Do not add broad seam prerequisites; keep one row = one session. | Verify row-level dependencies and execution order. |
| 2026-05-10 19:34:42 CEST | Dependency Pass completed | 202 row-owned sessions retained; no duplicates or non-row prerequisite sessions added. | Dependencies are row-local unless a downstream plan discovers a real missing harness and records it explicitly. | Write final reusable breakdown artifact. |
| 2026-05-10 19:34:50 CEST | Breakdown Write started | Generated the full target artifact from the parsed source matrix. | Final write must include every compatible artifact section plus row inventory and traceability. | Write session ledger, ordered breakdown, downstream path, and final status. |
| 2026-05-10 19:35:18 CEST | Breakdown Write completed | Wrote 202 row inventory rows, 202 ledger rows, and 202 ordered session entries. | Artifact is decomposition-ready; no implementation or tests were executed. | Use downstream rollout tooling when implementation work starts. |

## Recommended Plan Count

- recommended plan count: 202
- source rows inventoried: 202
- ordered sessions written: 202
- default posture held: one matrix row = one session
- added prerequisite sessions: 0
- added closure-only sessions: 0
- priority ordering for downstream execution: P0 rows in source order, then P1 rows in source order, then P2 rows in source order

## Decomposition Artifact

- artifact path: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- generated from source matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- generated on: 2026-05-10 19:35:18 CEST
- workflow executed in order: Matrix Intake -> Row Inventory -> Evidence Map -> Row Disposition -> Dependency Pass -> Breakdown Write
- adjacent breakdown present at intake: no; target was created as the decomposition work surface
- source rows inventoried: 202
- ordered sessions written: 202
- source status counts: Open=171, Partial=31
- row disposition counts: needs_code_and_tests=171, needs_tests_only=31
- implementation/tests executed during decomposition: none
- note: existing nearby repo tests and test-inventory notes are supporting evidence only; no row was marked `covered_in_repo` without exact private-matrix row closure proof

## Overall Closure Bar

- overall verdict: `still_open`
- closure bar: every source row currently marked `Open` or `Partial` must be closed by its own row-owned session or explicitly reclassified with exact evidence. A session is not closed until the source matrix row is updated to `Covered` or an equivalent closed state with concrete code/test/gate references.
- accepted follow-up rule: broad residual truth-alignment is not a substitute for row-owned code or test closure.
- row-owned truth rule: later closure must report final truth per source row id, not only per subsystem or broad group-chat reliability area.
- unsupported rows rule: no source row is currently marked `Unsupported`; if downstream work discovers unsupported product scope, it must update the row disposition explicitly rather than omitting the row.
- no-test-execution note: this decomposition performed lightweight inspection only and did not run gates.

## Source Of Truth

- primary matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- decomposition artifact: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- repo coverage inventory inspected as supporting context: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- bridge/native surfaces inspected as supporting context: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`
- current repo code and tests override stale matrix prose only when exact row evidence is named; this decomposition did not find exact private-matrix row-id closure outside the source matrix itself

## Matrix Row Inventory

| source row id | scenario | priority | source section or table | provisional row disposition | intended session id |
|---|---|---|---|---|---|
| BB-001 | Repeated native `Initialize` cannot strand Flutter behind an old callback | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-001 |
| BB-002 | Group commands before native initialization fail explicitly | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-002 |
| BB-003 | Private group create requires complete creator identity and key material | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-003 |
| BB-004 | Create returns a coherent group id, config, topic, group key, and epoch | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-004 |
| BB-005 | Unsupported group types are rejected without partial state | P1 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-005 |
| BB-006 | Legacy topic-name join helper is not used for private group onboarding | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-006 |
| BB-007 | Full-config join payload round-trips exactly through Dart and Go | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-007 |
| BB-008 | Already-joined recovery with newer key/config cannot report success while staying stale | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-008 |
| BB-009 | Leave removes the topic subscription used by validators and pubsub | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-009 |
| BB-010 | Leave failure does not mutate Flutter into a false removed or joined state | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-010 |
| BB-011 | Start, stop, and restart rejoin every persisted private group before acknowledging recovery | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-011 |
| BB-012 | Recovery acknowledgement cannot clear the recovery flag before join and inbox drain finish | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-012 |
| BB-013 | Bridge timeout responses are never interpreted as successful membership or send completion | P0 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-013 |
| BB-014 | GoBridge command map covers every private-group command used by helpers | P1 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-014 |
| BB-015 | Native null, missing plugin, platform error, and malformed JSON responses are safe | P1 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_tests_only | BB-015 |
| BB-016 | Description or extra metadata fields do not cause Dart/Go config drift | P1 | Bootstrap, Bridge Contract, and Topic-State Truth | needs_code_and_tests | BB-016 |
| ML-001 | Create a private group with A, B, and C and converge on the same active membership | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-001 |
| ML-002 | Add an online member and prove immediate live delivery | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-002 |
| ML-003 | Add an offline member and prove replay delivery after first reconnect | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-003 |
| ML-004 | Batch add with mixed success produces a truthful member set | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-004 |
| ML-005 | Remove an online member and converge remaining members | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-005 |
| ML-006 | Remove an offline member and converge after reconnect | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-006 |
| ML-007 | Re-add a previously removed member with current membership and key state | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-007 |
| ML-008 | Repeated add-remove-re-add cycles remain convergent | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-008 |
| ML-009 | Remove and re-add the same peer in rapid succession preserves event ordering | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-009 |
| ML-010 | Duplicate add is idempotent and does not duplicate members or keys | P1 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-010 |
| ML-011 | Duplicate remove is idempotent and does not revoke a later re-add | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-011 |
| ML-012 | Concurrent admin membership edits resolve deterministically | P1 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-012 |
| ML-013 | Non-admin or removed peer cannot create accepted membership changes | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-013 |
| ML-014 | Config update failure after local member insert rolls back or owns recovery | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-014 |
| ML-015 | Membership event timeline order matches structural membership state | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-015 |
| ML-016 | New member with no social-graph friendship still receives and renders messages | P1 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-016 |
| ML-017 | Removed member remains able to read old local history but not new content | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-017 |
| ML-018 | Invite decline, expiry, or cancellation never creates active membership | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-018 |
| ML-019 | Accepting a stale invite after removal is rejected or upgraded to latest re-add | P0 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-019 |
| ML-020 | Group creator or admin role changes do not break private delivery | P1 | Membership Lifecycle, Config Convergence, and Human-Visible Truth | needs_code_and_tests | ML-020 |
| KE-001 | Initial private group epoch is exactly 1 on every joined peer | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_tests_only | KE-001 |
| KE-002 | `generateNextKey` increments from the latest known epoch | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_tests_only | KE-002 |
| KE-003 | Stale lower-epoch `updateKey` cannot downgrade the validator | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-003 |
| KE-004 | Same-epoch same-key `updateKey` is idempotent | P1 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-004 |
| KE-005 | Same-epoch different-key conflict is rejected | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-005 |
| KE-006 | Removal rotates key and excludes removed peer from new key distribution | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-006 |
| KE-007 | Active members receive new key before the first message requiring it | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-007 |
| KE-008 | Re-added member receives the current epoch before being marked active | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-008 |
| KE-009 | Out-of-order config-before-key does not create a receive-dead member | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-009 |
| KE-010 | Out-of-order key-before-config does not grant unauthorized access | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-010 |
| KE-011 | Delayed old key update after re-add does not break C again | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-011 |
| KE-012 | Delayed old config after re-add does not remove active members | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-012 |
| KE-013 | Restart with missing Go key memory does not generate duplicate epoch | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-013 |
| KE-014 | Legacy `rotateKey` cannot mutate Go before distribution is durably owned | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-014 |
| KE-015 | Partial key distribution failure keeps sender state honest | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-015 |
| KE-016 | Re-invite package cannot carry an obsolete key after another rotation | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-016 |
| KE-017 | Received group event epoch matches local key state or triggers repair | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-017 |
| KE-018 | History replay respects key epoch windows | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-018 |
| KE-019 | Tampered key update payload is rejected and leaves current key intact | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-019 |
| KE-020 | Concurrent rotations allocate unique increasing epochs | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-020 |
| KE-021 | Removed member key material is not used for future direct or group inbox payloads | P0 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-021 |
| KE-022 | Key update errors are visible in diagnostics and recovery UI | P1 | Key Epoch, Rotation, and Stale-State Safety | needs_code_and_tests | KE-022 |
| DE-001 | Active members receive a live text message through group pubsub | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-001 |
| DE-002 | Rapid sequential messages preserve per-sender order | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-002 |
| DE-003 | Caller-supplied message id is preserved across publish, event, replay, and retry | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-003 |
| DE-004 | Live plus replay duplicate delivery dedupes without hiding state updates | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-004 |
| DE-005 | Sender self-echo is reconciled with the pending local row | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-005 |
| DE-006 | Publish result `topicPeers` does not overclaim recipient receipt | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-006 |
| DE-007 | Zero-peer publish stores or schedules offline delivery for active members | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-007 |
| DE-008 | Publish timeout does not create a permanently invisible pending message | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-008 |
| DE-009 | Group message events are routed to the group callback after Dart bridge reinitialize | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-009 |
| DE-010 | Native callback panic does not kill the Go dispatcher loop | P1 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-010 |
| DE-011 | Dispatcher pressure never drops message-bearing events below capacity | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-011 |
| DE-012 | Dispatcher overflow triggers replay recovery for dropped group events | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-012 |
| DE-013 | Message event schema is validated before persistence | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-013 |
| DE-014 | Decryption failure is diagnostic and recoverable, not a silent drop | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-014 |
| DE-015 | Payload parse failure does not poison the group stream | P1 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-015 |
| DE-016 | Validation rejection is surfaced to diagnostics | P1 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-016 |
| DE-017 | Membership event is applied before the first dependent content message | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-017 |
| DE-018 | Unknown group event type does not affect known event delivery | P2 | Message Publish, Receive, Event Dispatch, and Ordering | needs_tests_only | DE-018 |
| DE-019 | EventChannel done/error state triggers recovery, not permanent silence | P0 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-019 |
| DE-020 | Large message payloads do not starve the event dispatcher | P1 | Message Publish, Receive, Event Dispatch, and Ordering | needs_code_and_tests | DE-020 |
| IR-001 | Offline active member receives missed messages on reconnect | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-001 |
| IR-002 | Cursor-based retrieval is exactly-once across pages | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_tests_only | IR-002 |
| IR-003 | Timestamp-based retrieval has no boundary skips or duplicates | P1 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-003 |
| IR-004 | Replay does not expose post-removal messages to removed member | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-004 |
| IR-005 | Re-added member receives only post-readd replay | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-005 |
| IR-006 | Group inbox store targets exact active recipients at send time | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-006 |
| IR-007 | Inbox store failure owns retry without hiding message from sender | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-007 |
| IR-008 | Inbox retrieve failure does not advance cursor or ack state | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-008 |
| IR-009 | Replay item is not acknowledged before local persistence succeeds | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-009 |
| IR-010 | History gaps from cursor retrieval are parsed and surfaced | P1 | Offline Inbox, Replay, Cursoring, and History Repair | needs_tests_only | IR-010 |
| IR-011 | History repair range request validates gap identity and source peer | P1 | Offline Inbox, Replay, Cursoring, and History Repair | needs_tests_only | IR-011 |
| IR-012 | History repair verifies range hash and expected head before inserting messages | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-012 |
| IR-013 | Unauthorized repair source cannot inject messages | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-013 |
| IR-014 | Relay replay payloads are opaque to relay operators | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-014 |
| IR-015 | Replay supports text, quotes, image, video, files, GIFs, and voice uniformly | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-015 |
| IR-016 | Long offline retention cutoff is explicit and does not look like message loss | P1 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-016 |
| IR-017 | Replay after dispatcher overflow restores dropped live events | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-017 |
| IR-018 | Replay after restart drains before user is shown fully up to date | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-018 |
| IR-019 | Inbox retrieval preserves message id hidden inside encrypted envelope | P0 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-019 |
| IR-020 | Inbox repair cannot resurrect messages deleted by local policy as new unread items | P2 | Offline Inbox, Replay, Cursoring, and History Repair | needs_code_and_tests | IR-020 |
| RA-001 | Canonical remove-readd path preserves delivery for all active members | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-001 |
| RA-002 | Removed peer stays online and subscribed, then is re-added | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-002 |
| RA-003 | Removed peer is offline during removal and online during re-add | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-003 |
| RA-004 | Peer accepts old invite after being removed and before receiving new invite | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-004 |
| RA-005 | Old removal event delivered after re-add is ignored as stale | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-005 |
| RA-006 | Old key update delivered after re-add cannot downgrade C | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-006 |
| RA-007 | B misses removal but receives re-add and still converges | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-007 |
| RA-008 | C misses removal but receives re-add and does not retain removed-window access | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-008 |
| RA-009 | First message sent by re-added member is visible to existing members | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-009 |
| RA-010 | First incoming message to re-added member is visible before and after restart | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-010 |
| RA-011 | Immediate re-add before `group:leave` completes does not strand C | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-011 |
| RA-012 | Re-add same peer id with rotated device keys updates identity material | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-012 |
| RA-013 | Re-add same user with multiple devices has per-device truthful state | P1 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-013 |
| RA-014 | Removed member sending with old key after re-add does not poison the group | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-014 |
| RA-015 | Go and Flutter config converge after `ALREADY_JOINED` on re-add | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-015 |
| RA-016 | Delayed group inbox item from old removed interval is ignored after re-add | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-016 |
| RA-017 | Every active member can still receive after C churn, not only C | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-017 |
| RA-018 | Churn with alternating senders remains deterministic | P0 | Remove and Re-add Regression Suite | needs_code_and_tests | RA-018 |
| NW-001 | Full-mesh online group delivery works without relay fallback | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-001 |
| NW-002 | Relay-only or circuit-routed peers receive group messages | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-002 |
| NW-003 | Partition during removal and re-add heals to latest state | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-003 |
| NW-004 | Relay reconnect preserves or repairs group topic subscriptions | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-004 |
| NW-005 | Rendezvous rediscovery after membership change does not affect membership truth | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-005 |
| NW-006 | Peer disconnect does not equal group removal | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-006 |
| NW-007 | Topic peer count zero does not clear member list or disable recovery | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-007 |
| NW-008 | Duplicate libp2p connections do not duplicate visible messages | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-008 |
| NW-009 | Relay probe failure does not remove or mute group members | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-009 |
| NW-010 | Mobile background pause and foreground resume preserve group delivery | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-010 |
| NW-011 | Send during background or app unmount is either durable or blocked | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-011 |
| NW-012 | Long offline reconnect with multiple epoch changes converges | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-012 |
| NW-013 | Stop/start during key rotation does not fork epochs | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-013 |
| NW-014 | Flaky network chaos run maintains model invariants | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-014 |
| NW-015 | Dial and disconnect commands cannot corrupt group topic state | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle | needs_code_and_tests | NW-015 |
| PL-001 | Unicode and multiline text survives live and replay delivery | P1 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-001 |
| PL-002 | Media-only group message is allowed when text is empty | P0 | Payload Variants, Media, Quotes, and Reactions | needs_tests_only | PL-002 |
| PL-003 | Empty text with no media is rejected without local ghost row | P1 | Payload Variants, Media, Quotes, and Reactions | needs_tests_only | PL-003 |
| PL-004 | Quoted message id is preserved across live, replay, and re-add boundaries | P1 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-004 |
| PL-005 | Media allowedPeers match active membership at upload time | P0 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-005 |
| PL-006 | Removed member cannot download media uploaded after removal | P0 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-006 |
| PL-007 | Re-added member can download only post-readd media | P0 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-007 |
| PL-008 | Media upload progress coalescing never drops group messages | P1 | Payload Variants, Media, Quotes, and Reactions | needs_tests_only | PL-008 |
| PL-009 | Reaction from active member publishes and routes correctly | P1 | Payload Variants, Media, Quotes, and Reactions | needs_tests_only | PL-009 |
| PL-010 | Removed member reaction is rejected and does not mutate visible state | P0 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-010 |
| PL-011 | Re-added member reaction after current key update succeeds | P1 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-011 |
| PL-012 | Voice, GIF, file, image, and video payload schemas survive bridge publish opts | P1 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-012 |
| PL-013 | Partial media download cleans up local files and retries safely | P1 | Payload Variants, Media, Quotes, and Reactions | needs_tests_only | PL-013 |
| PL-014 | Media and blob metadata never leak group keys or plaintext | P0 | Payload Variants, Media, Quotes, and Reactions | needs_code_and_tests | PL-014 |
| UP-001 | Member list, local DB, and Go config stay in sync after every operation | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-001 |
| UP-002 | Timeline shows durable add, remove, and re-add events | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-002 |
| UP-003 | Compose box is enabled only for active members with current key | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-003 |
| UP-004 | Unread counts update correctly through removal and re-add | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-004 |
| UP-005 | Pending or failed invite state is visibly different from active member state | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-005 |
| UP-006 | Re-add banner or system row never reuses stale removed state | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-006 |
| UP-007 | No native bridge call is made while holding a DB write transaction | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_tests_only | UP-007 |
| UP-008 | Pending outbound group message survives restart and reconciles | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-008 |
| UP-009 | Username and sender identity render consistently after re-add | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-009 |
| UP-010 | Opening from notification routes to correct current group state | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-010 |
| UP-011 | Muted group suppresses notifications but not delivery | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-011 |
| UP-012 | Removed member receives no notifications for post-removal messages | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-012 |
| UP-013 | Group route change or widget unmount does not drop incoming events | P0 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-013 |
| UP-014 | Removed or pending member cannot be selected as share target | P1 | Local Persistence, UI Truth, Notifications, and Route Behavior | needs_code_and_tests | UP-014 |
| SV-001 | Never-member cannot publish to private group | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-001 |
| SV-002 | Removed member cannot publish with old key | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-002 |
| SV-003 | Re-added member cannot publish until current key/config is installed | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-003 |
| SV-004 | Forged sender identity or signature is rejected | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-004 |
| SV-005 | Tampered ciphertext or nonce is rejected without stream poisoning | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-005 |
| SV-006 | Replay attack of an old valid message is deduped or rejected | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-006 |
| SV-007 | Wrong group id or topic mismatch is rejected | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-007 |
| SV-008 | Unauthorized config update cannot be applied from network payload | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-008 |
| SV-009 | Invalid member public keys are rejected during add or join | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-009 |
| SV-010 | Duplicate message ids from different senders cannot overwrite valid rows | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-010 |
| SV-011 | Valid key but nonmember sender is rejected | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-011 |
| SV-012 | Peer id canonicalization prevents duplicate identity bypass | P1 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-012 |
| SV-013 | Logs and diagnostics never expose group keys or plaintext | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-013 |
| SV-014 | Relay operator cannot infer membership events beyond allowed metadata | P1 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-014 |
| SV-015 | Bridge helper decrypt failure returns explicit error, not TypeError-like crash | P1 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-015 |
| SV-016 | Bridge keygen failure does not throw an unclassified field access error | P0 | Security, Authorization, Tamper Resistance, and Privacy | needs_code_and_tests | SV-016 |
| OB-001 | Every group bridge command emits request, response, timing, and outcome flow events | P1 | Diagnostics, Observability, and Failure Attribution | needs_tests_only | OB-001 |
| OB-002 | Diagnostics include group id prefix, key epoch, message id, and membership operation id where safe | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-002 |
| OB-003 | Publish debug events explain zero peers, validator rejects, and fallback choices | P1 | Diagnostics, Observability, and Failure Attribution | needs_tests_only | OB-003 |
| OB-004 | Decryption failure diagnostics trigger key repair workflow | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-004 |
| OB-005 | Validation rejection is visible in Flutter diagnostics | P1 | Diagnostics, Observability, and Failure Attribution | needs_tests_only | OB-005 |
| OB-006 | Dispatcher pressure and overflow are logged and tied to recovery | P0 | Diagnostics, Observability, and Failure Attribution | needs_tests_only | OB-006 |
| OB-007 | EventChannel error or done produces a health failure or reinit attempt | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-007 |
| OB-008 | Retry job ownership is unambiguous for each degraded branch | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-008 |
| OB-009 | Unknown or malformed native events are counted and sanitized | P2 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-009 |
| OB-010 | Group callback exceptions are observable in tests | P1 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-010 |
| OB-011 | Release telemetry can answer who missed which message and why | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-011 |
| OB-012 | Sensitive diagnostic redaction is tested with real-looking secrets | P0 | Diagnostics, Observability, and Failure Attribution | needs_code_and_tests | OB-012 |
| ST-001 | Model-based membership state machine verifies every message recipient set | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-001 |
| ST-002 | Permutation test for add, remove, key, config, and message event ordering | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-002 |
| ST-003 | Epoch monotonicity property test | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-003 |
| ST-004 | Clock skew and timestamp fuzz for replay boundaries | P1 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-004 |
| ST-005 | High-throughput event storm does not lose messages without recovery | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-005 |
| ST-006 | Concurrent publishes during key rotation remain visible to active members | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-006 |
| ST-007 | Process death at every step of add, remove, and re-add recovers safely | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-007 |
| ST-008 | DB lock contention does not delay bridge event handling into message loss | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-008 |
| ST-009 | Maximum group size churn remains reliable | P1 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-009 |
| ST-010 | Invalid JSON and malformed bridge payload fuzzing | P1 | Stress, Fuzz, Model-Based, and Soak Tests | needs_tests_only | ST-010 |
| ST-011 | Rapid EventChannel reinitialize loop does not drop group callbacks permanently | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-011 |
| ST-012 | Topic subscription leak test after many churn cycles | P1 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-012 |
| ST-013 | Relay chaos with store, retrieve, cursor, and repair failures | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-013 |
| ST-014 | Long soak test with membership churn and periodic restarts | P0 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-014 |
| ST-015 | Seeded reproduction logs are stable enough for debugging | P1 | Stress, Fuzz, Model-Based, and Soak Tests | needs_code_and_tests | ST-015 |

## Row Traceability Rule

- every source row maps to exactly one session id in this artifact; no source rows were merged, dropped, or converted into broad seam buckets.
- session ids preserve the source row ids verbatim because every source row id is filename-safe.
- there are no `duplicate_of` relationships in this matrix decomposition.
- later closure work must report final truth per source row, even when multiple rows touch the same code-entry files, tests, or named gates.
- if a downstream plan discovers a real missing shared harness, it may record a dependency, but it must not replace row-owned closure for the affected source rows.

## Evidence Map Summary

| row family | focus | likely code-entry files | nearby tests / evidence candidates | proof ownership |
|---|---|---|---|---|
| BB | Bootstrap / bridge contract | `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart` | `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` | Flutter/Go bridge-owned proof with MethodChannel, native bridge, and recovery orchestration coverage. |
| ML | Membership lifecycle | `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart` | `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` | Flutter-owned membership and invite flow proof, with optional simulator or real multi-party confirmation where the row requires it. |
| KE | Key epoch and stale-state safety | `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go` | `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` | Flutter/Go key-state proof; stale epoch and split-key rows may need raw bridge or fake-network ordering control. |
| DE | Delivery and event dispatch | `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go` | `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` | Message send/receive and dispatcher proof; overflow rows require explicit recovery or replay evidence. |
| IR | Inbox replay and history repair | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go` | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` | Offline inbox, replay, cursor, and history repair proof with persistence-before-ack ownership. |
| RA | Remove and re-add regression | `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go` | `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` | Remove/re-add proof across membership, key, replay, and Go bridge state; exact churn rows require row-specific ordering assertions. |
| NW | Network / relay / mobile lifecycle | `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go` | `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` | Network, relay, and lifecycle proof; configured simulator or relay evidence may be required by row gates. |
| PL | Payload / media / reactions | `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go` | `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` | Payload, media, reaction, and attachment proof; allowed-peer and privacy rows need explicit recipient and metadata capture. |
| UP | Persistence / UI / notifications | `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart` | `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` | Flutter UI, persistence, route, notification, unread, and DB/bridge transaction proof. |
| SV | Security and privacy | `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart` | `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` | Security, validator, tamper, and redaction proof; raw envelope injection may be needed for adversarial rows. |
| OB | Observability | `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go` | `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` | Diagnostics and observability proof; rows close only when attribution is actionable and secrets are redacted. |
| ST | Stress and soak | `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go` | `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` | Stress, fuzz, property, and soak proof; deterministic seeds and invariant logs are part of the row contract. |

## Session Ledger

| session id | source row id | priority | row disposition | session classification | execution ownership | dependency | intended plan file |
|---|---|---|---|---|---|---|---|
| BB-001 | BB-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md |
| BB-002 | BB-002 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-002-plan.md |
| BB-003 | BB-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md |
| BB-004 | BB-004 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md |
| BB-006 | BB-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md |
| BB-007 | BB-007 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md |
| BB-008 | BB-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md |
| BB-009 | BB-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md |
| BB-010 | BB-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md |
| BB-011 | BB-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md |
| BB-012 | BB-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md |
| BB-013 | BB-013 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-013-plan.md |
| ML-001 | ML-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-001-plan.md |
| ML-002 | ML-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-002-plan.md |
| ML-003 | ML-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-003-plan.md |
| ML-004 | ML-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-004-plan.md |
| ML-005 | ML-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-005-plan.md |
| ML-006 | ML-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md |
| ML-007 | ML-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md |
| ML-008 | ML-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md |
| ML-009 | ML-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md |
| ML-011 | ML-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-011-plan.md |
| ML-013 | ML-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-013-plan.md |
| ML-014 | ML-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-014-plan.md |
| ML-015 | ML-015 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-015-plan.md |
| ML-017 | ML-017 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-017-plan.md |
| ML-018 | ML-018 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-018-plan.md |
| ML-019 | ML-019 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-019-plan.md |
| KE-001 | KE-001 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-001-plan.md |
| KE-002 | KE-002 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-002-plan.md |
| KE-003 | KE-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-003-plan.md |
| KE-005 | KE-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-005-plan.md |
| KE-006 | KE-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-006-plan.md |
| KE-007 | KE-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-007-plan.md |
| KE-008 | KE-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-008-plan.md |
| KE-009 | KE-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md |
| KE-010 | KE-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-010-plan.md |
| KE-011 | KE-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-011-plan.md |
| KE-012 | KE-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-012-plan.md |
| KE-013 | KE-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-013-plan.md |
| KE-014 | KE-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-014-plan.md |
| KE-015 | KE-015 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-015-plan.md |
| KE-016 | KE-016 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-016-plan.md |
| KE-017 | KE-017 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-017-plan.md |
| KE-018 | KE-018 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-018-plan.md |
| KE-019 | KE-019 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-019-plan.md |
| KE-020 | KE-020 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-020-plan.md |
| KE-021 | KE-021 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-021-plan.md |
| DE-001 | DE-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-001-plan.md |
| DE-002 | DE-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-002-plan.md |
| DE-003 | DE-003 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-003-plan.md |
| DE-004 | DE-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-004-plan.md |
| DE-005 | DE-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-005-plan.md |
| DE-006 | DE-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-006-plan.md |
| DE-007 | DE-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-007-plan.md |
| DE-008 | DE-008 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-008-plan.md |
| DE-009 | DE-009 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-009-plan.md |
| DE-011 | DE-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-011-plan.md |
| DE-012 | DE-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-012-plan.md |
| DE-013 | DE-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-013-plan.md |
| DE-014 | DE-014 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-014-plan.md |
| DE-017 | DE-017 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-017-plan.md |
| DE-019 | DE-019 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-019-plan.md |
| IR-001 | IR-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-001-plan.md |
| IR-002 | IR-002 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-002-plan.md |
| IR-004 | IR-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-004-plan.md |
| IR-005 | IR-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-005-plan.md |
| IR-006 | IR-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-006-plan.md |
| IR-007 | IR-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-007-plan.md |
| IR-008 | IR-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-008-plan.md |
| IR-009 | IR-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-009-plan.md |
| IR-012 | IR-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-012-plan.md |
| IR-013 | IR-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-013-plan.md |
| IR-014 | IR-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-014-plan.md |
| IR-015 | IR-015 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-015-plan.md |
| IR-017 | IR-017 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-017-plan.md |
| IR-018 | IR-018 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-018-plan.md |
| IR-019 | IR-019 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-019-plan.md |
| RA-001 | RA-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-001-plan.md |
| RA-002 | RA-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-002-plan.md |
| RA-003 | RA-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-003-plan.md |
| RA-004 | RA-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-004-plan.md |
| RA-005 | RA-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-005-plan.md |
| RA-006 | RA-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-006-plan.md |
| RA-007 | RA-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-007-plan.md |
| RA-008 | RA-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-008-plan.md |
| RA-009 | RA-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-009-plan.md |
| RA-010 | RA-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-010-plan.md |
| RA-011 | RA-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-011-plan.md |
| RA-012 | RA-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-012-plan.md |
| RA-014 | RA-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-014-plan.md |
| RA-015 | RA-015 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-015-plan.md |
| RA-016 | RA-016 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-016-plan.md |
| RA-017 | RA-017 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-017-plan.md |
| RA-018 | RA-018 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-018-plan.md |
| NW-001 | NW-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-001-plan.md |
| NW-002 | NW-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-002-plan.md |
| NW-003 | NW-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-003-plan.md |
| NW-004 | NW-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-004-plan.md |
| NW-006 | NW-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-006-plan.md |
| NW-007 | NW-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-007-plan.md |
| NW-010 | NW-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-010-plan.md |
| NW-011 | NW-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-011-plan.md |
| NW-012 | NW-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-012-plan.md |
| NW-013 | NW-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md |
| NW-014 | NW-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-014-plan.md |
| PL-002 | PL-002 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-002-plan.md |
| PL-005 | PL-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-005-plan.md |
| PL-006 | PL-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-006-plan.md |
| PL-007 | PL-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-007-plan.md |
| PL-010 | PL-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-010-plan.md |
| PL-014 | PL-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-014-plan.md |
| UP-001 | UP-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-001-plan.md |
| UP-003 | UP-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-003-plan.md |
| UP-005 | UP-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-005-plan.md |
| UP-007 | UP-007 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-007-plan.md |
| UP-008 | UP-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-008-plan.md |
| UP-012 | UP-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-012-plan.md |
| UP-013 | UP-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-013-plan.md |
| SV-001 | SV-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-001-plan.md |
| SV-002 | SV-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-002-plan.md |
| SV-003 | SV-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-003-plan.md |
| SV-004 | SV-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-004-plan.md |
| SV-005 | SV-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-005-plan.md |
| SV-006 | SV-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-006-plan.md |
| SV-007 | SV-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-007-plan.md |
| SV-008 | SV-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-008-plan.md |
| SV-009 | SV-009 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-009-plan.md |
| SV-010 | SV-010 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-010-plan.md |
| SV-011 | SV-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-011-plan.md |
| SV-013 | SV-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-013-plan.md |
| SV-016 | SV-016 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-016-plan.md |
| OB-002 | OB-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-002-plan.md |
| OB-004 | OB-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-004-plan.md |
| OB-006 | OB-006 | P0 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-006-plan.md |
| OB-007 | OB-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-007-plan.md |
| OB-008 | OB-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-008-plan.md |
| OB-011 | OB-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-011-plan.md |
| OB-012 | OB-012 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-012-plan.md |
| ST-001 | ST-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-001-plan.md |
| ST-002 | ST-002 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-002-plan.md |
| ST-003 | ST-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-003-plan.md |
| ST-005 | ST-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-005-plan.md |
| ST-006 | ST-006 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-006-plan.md |
| ST-007 | ST-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-007-plan.md |
| ST-008 | ST-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-008-plan.md |
| ST-011 | ST-011 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-011-plan.md |
| ST-013 | ST-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-013-plan.md |
| ST-014 | ST-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-014-plan.md |
| BB-005 | BB-005 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-005-plan.md |
| BB-014 | BB-014 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-014-plan.md |
| BB-015 | BB-015 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-015-plan.md |
| BB-016 | BB-016 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-016-plan.md |
| ML-010 | ML-010 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-010-plan.md |
| ML-012 | ML-012 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-012-plan.md |
| ML-016 | ML-016 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-016-plan.md |
| ML-020 | ML-020 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-020-plan.md |
| KE-004 | KE-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-004-plan.md |
| KE-022 | KE-022 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-022-plan.md |
| DE-010 | DE-010 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-010-plan.md |
| DE-015 | DE-015 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-015-plan.md |
| DE-016 | DE-016 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-016-plan.md |
| DE-020 | DE-020 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-020-plan.md |
| IR-003 | IR-003 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-003-plan.md |
| IR-010 | IR-010 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-010-plan.md |
| IR-011 | IR-011 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-011-plan.md |
| IR-016 | IR-016 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-016-plan.md |
| RA-013 | RA-013 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-013-plan.md |
| NW-005 | NW-005 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-005-plan.md |
| NW-008 | NW-008 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-008-plan.md |
| NW-009 | NW-009 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-009-plan.md |
| NW-015 | NW-015 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-015-plan.md |
| PL-001 | PL-001 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-001-plan.md |
| PL-003 | PL-003 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-003-plan.md |
| PL-004 | PL-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-004-plan.md |
| PL-008 | PL-008 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-008-plan.md |
| PL-009 | PL-009 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-009-plan.md |
| PL-011 | PL-011 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-011-plan.md |
| PL-012 | PL-012 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-012-plan.md |
| PL-013 | PL-013 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-013-plan.md |
| UP-002 | UP-002 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-002-plan.md |
| UP-004 | UP-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-004-plan.md |
| UP-006 | UP-006 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-006-plan.md |
| UP-009 | UP-009 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-009-plan.md |
| UP-010 | UP-010 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-010-plan.md |
| UP-011 | UP-011 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-011-plan.md |
| UP-014 | UP-014 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-014-plan.md |
| SV-012 | SV-012 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-012-plan.md |
| SV-014 | SV-014 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-014-plan.md |
| SV-015 | SV-015 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-015-plan.md |
| OB-001 | OB-001 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-001-plan.md |
| OB-003 | OB-003 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-003-plan.md |
| OB-005 | OB-005 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-005-plan.md |
| OB-010 | OB-010 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-010-plan.md |
| ST-004 | ST-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-004-plan.md |
| ST-009 | ST-009 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-009-plan.md |
| ST-010 | ST-010 | P1 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-010-plan.md |
| ST-012 | ST-012 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-012-plan.md |
| ST-015 | ST-015 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-015-plan.md |
| DE-018 | DE-018 | P2 | needs_tests_only | implementation-ready | tests only | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-018-plan.md |
| IR-020 | IR-020 | P2 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-020-plan.md |
| OB-009 | OB-009 | P2 | needs_code_and_tests | implementation-ready | code changes and tests | none | Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-009-plan.md |

## Ordered Session Breakdown

Sessions are ordered for downstream execution by P0, then P1, then P2, preserving source order within each priority. Each session owns exactly one matrix row.

### Session BB-001
- source row id: `BB-001`
- scenario title: Repeated native `Initialize` cannot strand Flutter behind an old callback
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `109`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-001` only: Repeated native `Initialize` cannot strand Flutter behind an old callback. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-001`: Repeated native `Initialize` cannot strand Flutter behind an old callback. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-002
- source row id: `BB-002`
- scenario title: Group commands before native initialization fail explicitly
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `110`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-002-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-002` only: Group commands before native initialization fail explicitly. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-002`: Group commands before native initialization fail explicitly. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-003
- source row id: `BB-003`
- scenario title: Private group create requires complete creator identity and key material
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `111`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-003` only: Private group create requires complete creator identity and key material. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-003`: Private group create requires complete creator identity and key material. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-004
- source row id: `BB-004`
- scenario title: Create returns a coherent group id, config, topic, group key, and epoch
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `112`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-004` only: Create returns a coherent group id, config, topic, group key, and epoch. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-004`: Create returns a coherent group id, config, topic, group key, and epoch. Required source gates: Unit=Required, Integration=Required, Smoke=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-006
- source row id: `BB-006`
- scenario title: Legacy topic-name join helper is not used for private group onboarding
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `114`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-006` only: Legacy topic-name join helper is not used for private group onboarding. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-006`: Legacy topic-name join helper is not used for private group onboarding. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-007
- source row id: `BB-007`
- scenario title: Full-config join payload round-trips exactly through Dart and Go
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `115`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-007` only: Full-config join payload round-trips exactly through Dart and Go. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-007`: Full-config join payload round-trips exactly through Dart and Go. Required source gates: Unit=Required, Integration=Required, Smoke=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-008
- source row id: `BB-008`
- scenario title: Already-joined recovery with newer key/config cannot report success while staying stale
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `116`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-008` only: Already-joined recovery with newer key/config cannot report success while staying stale. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-008`: Already-joined recovery with newer key/config cannot report success while staying stale. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-009
- source row id: `BB-009`
- scenario title: Leave removes the topic subscription used by validators and pubsub
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `117`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-009` only: Leave removes the topic subscription used by validators and pubsub. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-009`: Leave removes the topic subscription used by validators and pubsub. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-010
- source row id: `BB-010`
- scenario title: Leave failure does not mutate Flutter into a false removed or joined state
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `118`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-010` only: Leave failure does not mutate Flutter into a false removed or joined state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-010`: Leave failure does not mutate Flutter into a false removed or joined state. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-011
- source row id: `BB-011`
- scenario title: Start, stop, and restart rejoin every persisted private group before acknowledging recovery
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `119`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-011` only: Start, stop, and restart rejoin every persisted private group before acknowledging recovery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-011`: Start, stop, and restart rejoin every persisted private group before acknowledging recovery. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-012
- source row id: `BB-012`
- scenario title: Recovery acknowledgement cannot clear the recovery flag before join and inbox drain finish
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `120`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-012` only: Recovery acknowledgement cannot clear the recovery flag before join and inbox drain finish. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-012`: Recovery acknowledgement cannot clear the recovery flag before join and inbox drain finish. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-013
- source row id: `BB-013`
- scenario title: Bridge timeout responses are never interpreted as successful membership or send completion
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `121`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-013-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-013` only: Bridge timeout responses are never interpreted as successful membership or send completion. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-013`: Bridge timeout responses are never interpreted as successful membership or send completion. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-001
- source row id: `ML-001`
- scenario title: Create a private group with A, B, and C and converge on the same active membership
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `130`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-001` only: Create a private group with A, B, and C and converge on the same active membership. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-001`: Create a private group with A, B, and C and converge on the same active membership. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-002
- source row id: `ML-002`
- scenario title: Add an online member and prove immediate live delivery
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `131`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-002` only: Add an online member and prove immediate live delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-002`: Add an online member and prove immediate live delivery. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-003
- source row id: `ML-003`
- scenario title: Add an offline member and prove replay delivery after first reconnect
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `132`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-003` only: Add an offline member and prove replay delivery after first reconnect. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-003`: Add an offline member and prove replay delivery after first reconnect. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-004
- source row id: `ML-004`
- scenario title: Batch add with mixed success produces a truthful member set
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `133`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-004` only: Batch add with mixed success produces a truthful member set. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-004`: Batch add with mixed success produces a truthful member set. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-005
- source row id: `ML-005`
- scenario title: Remove an online member and converge remaining members
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `134`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-005` only: Remove an online member and converge remaining members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-005`: Remove an online member and converge remaining members. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-006
- source row id: `ML-006`
- scenario title: Remove an offline member and converge after reconnect
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `135`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-006` only: Remove an offline member and converge after reconnect. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-006`: Remove an offline member and converge after reconnect. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-007
- source row id: `ML-007`
- scenario title: Re-add a previously removed member with current membership and key state
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `136`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-007` only: Re-add a previously removed member with current membership and key state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-007`: Re-add a previously removed member with current membership and key state. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-008
- source row id: `ML-008`
- scenario title: Repeated add-remove-re-add cycles remain convergent
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `137`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-008` only: Repeated add-remove-re-add cycles remain convergent. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-008`: Repeated add-remove-re-add cycles remain convergent. Required source gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-009
- source row id: `ML-009`
- scenario title: Remove and re-add the same peer in rapid succession preserves event ordering
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `138`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-009` only: Remove and re-add the same peer in rapid succession preserves event ordering. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-009`: Remove and re-add the same peer in rapid succession preserves event ordering. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-011
- source row id: `ML-011`
- scenario title: Duplicate remove is idempotent and does not revoke a later re-add
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `140`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-011` only: Duplicate remove is idempotent and does not revoke a later re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-011`: Duplicate remove is idempotent and does not revoke a later re-add. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-013
- source row id: `ML-013`
- scenario title: Non-admin or removed peer cannot create accepted membership changes
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `142`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-013` only: Non-admin or removed peer cannot create accepted membership changes. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-013`: Non-admin or removed peer cannot create accepted membership changes. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-014
- source row id: `ML-014`
- scenario title: Config update failure after local member insert rolls back or owns recovery
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `143`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-014` only: Config update failure after local member insert rolls back or owns recovery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-014`: Config update failure after local member insert rolls back or owns recovery. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-015
- source row id: `ML-015`
- scenario title: Membership event timeline order matches structural membership state
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `144`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-015` only: Membership event timeline order matches structural membership state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-015`: Membership event timeline order matches structural membership state. Required source gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-017
- source row id: `ML-017`
- scenario title: Removed member remains able to read old local history but not new content
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `146`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-017-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-017` only: Removed member remains able to read old local history but not new content. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-017` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-017`: Removed member remains able to read old local history but not new content. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-017-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-017`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-018
- source row id: `ML-018`
- scenario title: Invite decline, expiry, or cancellation never creates active membership
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `147`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-018-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-018` only: Invite decline, expiry, or cancellation never creates active membership. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-018` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-018`: Invite decline, expiry, or cancellation never creates active membership. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-018-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-018`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-019
- source row id: `ML-019`
- scenario title: Accepting a stale invite after removal is rejected or upgraded to latest re-add
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `148`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-019-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-019` only: Accepting a stale invite after removal is rejected or upgraded to latest re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-019` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-019`: Accepting a stale invite after removal is rejected or upgraded to latest re-add. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-019-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-019`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-001
- source row id: `KE-001`
- scenario title: Initial private group epoch is exactly 1 on every joined peer
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `155`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-001-plan.md`
- exact scope: Add row-specific regression proof for source row `KE-001` only: Initial private group epoch is exactly 1 on every joined peer. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-001`: Initial private group epoch is exactly 1 on every joined peer. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-002
- source row id: `KE-002`
- scenario title: `generateNextKey` increments from the latest known epoch
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `156`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-002-plan.md`
- exact scope: Add row-specific regression proof for source row `KE-002` only: `generateNextKey` increments from the latest known epoch. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-002`: `generateNextKey` increments from the latest known epoch. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-003
- source row id: `KE-003`
- scenario title: Stale lower-epoch `updateKey` cannot downgrade the validator
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `157`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-003` only: Stale lower-epoch `updateKey` cannot downgrade the validator. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-003`: Stale lower-epoch `updateKey` cannot downgrade the validator. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-005
- source row id: `KE-005`
- scenario title: Same-epoch different-key conflict is rejected
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `159`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-005` only: Same-epoch different-key conflict is rejected. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-005`: Same-epoch different-key conflict is rejected. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-006
- source row id: `KE-006`
- scenario title: Removal rotates key and excludes removed peer from new key distribution
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `160`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-006` only: Removal rotates key and excludes removed peer from new key distribution. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-006`: Removal rotates key and excludes removed peer from new key distribution. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-007
- source row id: `KE-007`
- scenario title: Active members receive new key before the first message requiring it
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `161`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-007` only: Active members receive new key before the first message requiring it. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-007`: Active members receive new key before the first message requiring it. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-008
- source row id: `KE-008`
- scenario title: Re-added member receives the current epoch before being marked active
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `162`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-008` only: Re-added member receives the current epoch before being marked active. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-008`: Re-added member receives the current epoch before being marked active. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-009
- source row id: `KE-009`
- scenario title: Out-of-order config-before-key does not create a receive-dead member
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `163`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-009` only: Out-of-order config-before-key does not create a receive-dead member. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-009`: Out-of-order config-before-key does not create a receive-dead member. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-010
- source row id: `KE-010`
- scenario title: Out-of-order key-before-config does not grant unauthorized access
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `164`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-010` only: Out-of-order key-before-config does not grant unauthorized access. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-010`: Out-of-order key-before-config does not grant unauthorized access. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-011
- source row id: `KE-011`
- scenario title: Delayed old key update after re-add does not break C again
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `165`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-011` only: Delayed old key update after re-add does not break C again. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-011`: Delayed old key update after re-add does not break C again. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-012
- source row id: `KE-012`
- scenario title: Delayed old config after re-add does not remove active members
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `166`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-012` only: Delayed old config after re-add does not remove active members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-012`: Delayed old config after re-add does not remove active members. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-013
- source row id: `KE-013`
- scenario title: Restart with missing Go key memory does not generate duplicate epoch
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `167`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-013` only: Restart with missing Go key memory does not generate duplicate epoch. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-013`: Restart with missing Go key memory does not generate duplicate epoch. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-014
- source row id: `KE-014`
- scenario title: Legacy `rotateKey` cannot mutate Go before distribution is durably owned
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `168`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-014` only: Legacy `rotateKey` cannot mutate Go before distribution is durably owned. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-014`: Legacy `rotateKey` cannot mutate Go before distribution is durably owned. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-015
- source row id: `KE-015`
- scenario title: Partial key distribution failure keeps sender state honest
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `169`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-015` only: Partial key distribution failure keeps sender state honest. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-015`: Partial key distribution failure keeps sender state honest. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-016
- source row id: `KE-016`
- scenario title: Re-invite package cannot carry an obsolete key after another rotation
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `170`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-016` only: Re-invite package cannot carry an obsolete key after another rotation. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-016`: Re-invite package cannot carry an obsolete key after another rotation. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-017
- source row id: `KE-017`
- scenario title: Received group event epoch matches local key state or triggers repair
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `171`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-017-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-017` only: Received group event epoch matches local key state or triggers repair. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-017` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-017`: Received group event epoch matches local key state or triggers repair. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-017-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-017`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-018
- source row id: `KE-018`
- scenario title: History replay respects key epoch windows
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `172`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-018-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-018` only: History replay respects key epoch windows. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-018` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-018`: History replay respects key epoch windows. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-018-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-018`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-019
- source row id: `KE-019`
- scenario title: Tampered key update payload is rejected and leaves current key intact
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `173`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-019-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-019` only: Tampered key update payload is rejected and leaves current key intact. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-019` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-019`: Tampered key update payload is rejected and leaves current key intact. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-019-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-019`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-020
- source row id: `KE-020`
- scenario title: Concurrent rotations allocate unique increasing epochs
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `174`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-020-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-020` only: Concurrent rotations allocate unique increasing epochs. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-020` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-020`: Concurrent rotations allocate unique increasing epochs. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-020-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-020`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-021
- source row id: `KE-021`
- scenario title: Removed member key material is not used for future direct or group inbox payloads
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `175`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-021-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-021` only: Removed member key material is not used for future direct or group inbox payloads. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-021` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-021`: Removed member key material is not used for future direct or group inbox payloads. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-021-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-021`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-001
- source row id: `DE-001`
- scenario title: Active members receive a live text message through group pubsub
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `182`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-001` only: Active members receive a live text message through group pubsub. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-001`: Active members receive a live text message through group pubsub. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-002
- source row id: `DE-002`
- scenario title: Rapid sequential messages preserve per-sender order
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `183`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-002` only: Rapid sequential messages preserve per-sender order. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-002`: Rapid sequential messages preserve per-sender order. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-003
- source row id: `DE-003`
- scenario title: Caller-supplied message id is preserved across publish, event, replay, and retry
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `184`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-003-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-003` only: Caller-supplied message id is preserved across publish, event, replay, and retry. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-003`: Caller-supplied message id is preserved across publish, event, replay, and retry. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-004
- source row id: `DE-004`
- scenario title: Live plus replay duplicate delivery dedupes without hiding state updates
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `185`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-004` only: Live plus replay duplicate delivery dedupes without hiding state updates. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-004`: Live plus replay duplicate delivery dedupes without hiding state updates. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-005
- source row id: `DE-005`
- scenario title: Sender self-echo is reconciled with the pending local row
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `186`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-005` only: Sender self-echo is reconciled with the pending local row. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-005`: Sender self-echo is reconciled with the pending local row. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-006
- source row id: `DE-006`
- scenario title: Publish result `topicPeers` does not overclaim recipient receipt
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `187`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-006` only: Publish result `topicPeers` does not overclaim recipient receipt. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-006`: Publish result `topicPeers` does not overclaim recipient receipt. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-007
- source row id: `DE-007`
- scenario title: Zero-peer publish stores or schedules offline delivery for active members
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `188`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-007` only: Zero-peer publish stores or schedules offline delivery for active members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-007`: Zero-peer publish stores or schedules offline delivery for active members. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-008
- source row id: `DE-008`
- scenario title: Publish timeout does not create a permanently invisible pending message
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `189`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-008-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-008` only: Publish timeout does not create a permanently invisible pending message. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-008`: Publish timeout does not create a permanently invisible pending message. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-009
- source row id: `DE-009`
- scenario title: Group message events are routed to the group callback after Dart bridge reinitialize
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `190`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-009-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-009` only: Group message events are routed to the group callback after Dart bridge reinitialize. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-009`: Group message events are routed to the group callback after Dart bridge reinitialize. Required source gates: Unit=Required, Integration=Recommended, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Recommended, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-011
- source row id: `DE-011`
- scenario title: Dispatcher pressure never drops message-bearing events below capacity
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `192`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-011` only: Dispatcher pressure never drops message-bearing events below capacity. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-011`: Dispatcher pressure never drops message-bearing events below capacity. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-012
- source row id: `DE-012`
- scenario title: Dispatcher overflow triggers replay recovery for dropped group events
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `193`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-012` only: Dispatcher overflow triggers replay recovery for dropped group events. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-012`: Dispatcher overflow triggers replay recovery for dropped group events. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-013
- source row id: `DE-013`
- scenario title: Message event schema is validated before persistence
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `194`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-013` only: Message event schema is validated before persistence. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-013`: Message event schema is validated before persistence. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-014
- source row id: `DE-014`
- scenario title: Decryption failure is diagnostic and recoverable, not a silent drop
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `195`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-014-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-014` only: Decryption failure is diagnostic and recoverable, not a silent drop. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-014`: Decryption failure is diagnostic and recoverable, not a silent drop. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-017
- source row id: `DE-017`
- scenario title: Membership event is applied before the first dependent content message
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `198`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-017-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-017` only: Membership event is applied before the first dependent content message. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-017` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-017`: Membership event is applied before the first dependent content message. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-017-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-017`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-019
- source row id: `DE-019`
- scenario title: EventChannel done/error state triggers recovery, not permanent silence
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `200`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-019-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-019` only: EventChannel done/error state triggers recovery, not permanent silence. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-019` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-019`: EventChannel done/error state triggers recovery, not permanent silence. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-019-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-019`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-001
- source row id: `IR-001`
- scenario title: Offline active member receives missed messages on reconnect
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `207`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-001` only: Offline active member receives missed messages on reconnect. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-001`: Offline active member receives missed messages on reconnect. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-002
- source row id: `IR-002`
- scenario title: Cursor-based retrieval is exactly-once across pages
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `208`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-002-plan.md`
- exact scope: Add row-specific regression proof for source row `IR-002` only: Cursor-based retrieval is exactly-once across pages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-002`: Cursor-based retrieval is exactly-once across pages. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-004
- source row id: `IR-004`
- scenario title: Replay does not expose post-removal messages to removed member
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `210`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-004` only: Replay does not expose post-removal messages to removed member. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-004`: Replay does not expose post-removal messages to removed member. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-005
- source row id: `IR-005`
- scenario title: Re-added member receives only post-readd replay
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `211`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-005` only: Re-added member receives only post-readd replay. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-005`: Re-added member receives only post-readd replay. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-006
- source row id: `IR-006`
- scenario title: Group inbox store targets exact active recipients at send time
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `212`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-006` only: Group inbox store targets exact active recipients at send time. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-006`: Group inbox store targets exact active recipients at send time. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-007
- source row id: `IR-007`
- scenario title: Inbox store failure owns retry without hiding message from sender
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `213`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-007` only: Inbox store failure owns retry without hiding message from sender. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-007`: Inbox store failure owns retry without hiding message from sender. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-008
- source row id: `IR-008`
- scenario title: Inbox retrieve failure does not advance cursor or ack state
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `214`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-008` only: Inbox retrieve failure does not advance cursor or ack state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-008`: Inbox retrieve failure does not advance cursor or ack state. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-009
- source row id: `IR-009`
- scenario title: Replay item is not acknowledged before local persistence succeeds
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `215`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-009` only: Replay item is not acknowledged before local persistence succeeds. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-009`: Replay item is not acknowledged before local persistence succeeds. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-012
- source row id: `IR-012`
- scenario title: History repair verifies range hash and expected head before inserting messages
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `218`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-012` only: History repair verifies range hash and expected head before inserting messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-012`: History repair verifies range hash and expected head before inserting messages. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-013
- source row id: `IR-013`
- scenario title: Unauthorized repair source cannot inject messages
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `219`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-013` only: Unauthorized repair source cannot inject messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-013`: Unauthorized repair source cannot inject messages. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-014
- source row id: `IR-014`
- scenario title: Relay replay payloads are opaque to relay operators
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `220`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-014` only: Relay replay payloads are opaque to relay operators. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-014`: Relay replay payloads are opaque to relay operators. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-015
- source row id: `IR-015`
- scenario title: Replay supports text, quotes, image, video, files, GIFs, and voice uniformly
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `221`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-015` only: Replay supports text, quotes, image, video, files, GIFs, and voice uniformly. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-015`: Replay supports text, quotes, image, video, files, GIFs, and voice uniformly. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-017
- source row id: `IR-017`
- scenario title: Replay after dispatcher overflow restores dropped live events
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `223`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-017-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-017` only: Replay after dispatcher overflow restores dropped live events. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-017` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-017`: Replay after dispatcher overflow restores dropped live events. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-017-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-017`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-018
- source row id: `IR-018`
- scenario title: Replay after restart drains before user is shown fully up to date
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `224`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-018-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-018` only: Replay after restart drains before user is shown fully up to date. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-018` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-018`: Replay after restart drains before user is shown fully up to date. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-018-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-018`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-019
- source row id: `IR-019`
- scenario title: Inbox retrieval preserves message id hidden inside encrypted envelope
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `225`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-019-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-019` only: Inbox retrieval preserves message id hidden inside encrypted envelope. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-019` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-019`: Inbox retrieval preserves message id hidden inside encrypted envelope. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-019-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-019`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-001
- source row id: `RA-001`
- scenario title: Canonical remove-readd path preserves delivery for all active members
- source section: Remove and Re-add Regression Suite
- source line: `232`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-001` only: Canonical remove-readd path preserves delivery for all active members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-001`: Canonical remove-readd path preserves delivery for all active members. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-002
- source row id: `RA-002`
- scenario title: Removed peer stays online and subscribed, then is re-added
- source section: Remove and Re-add Regression Suite
- source line: `233`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-002` only: Removed peer stays online and subscribed, then is re-added. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-002`: Removed peer stays online and subscribed, then is re-added. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-003
- source row id: `RA-003`
- scenario title: Removed peer is offline during removal and online during re-add
- source section: Remove and Re-add Regression Suite
- source line: `234`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-003` only: Removed peer is offline during removal and online during re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-003`: Removed peer is offline during removal and online during re-add. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-004
- source row id: `RA-004`
- scenario title: Peer accepts old invite after being removed and before receiving new invite
- source section: Remove and Re-add Regression Suite
- source line: `235`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-004` only: Peer accepts old invite after being removed and before receiving new invite. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-004`: Peer accepts old invite after being removed and before receiving new invite. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-005
- source row id: `RA-005`
- scenario title: Old removal event delivered after re-add is ignored as stale
- source section: Remove and Re-add Regression Suite
- source line: `236`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-005` only: Old removal event delivered after re-add is ignored as stale. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-005`: Old removal event delivered after re-add is ignored as stale. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-006
- source row id: `RA-006`
- scenario title: Old key update delivered after re-add cannot downgrade C
- source section: Remove and Re-add Regression Suite
- source line: `237`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-006` only: Old key update delivered after re-add cannot downgrade C. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-006`: Old key update delivered after re-add cannot downgrade C. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-007
- source row id: `RA-007`
- scenario title: B misses removal but receives re-add and still converges
- source section: Remove and Re-add Regression Suite
- source line: `238`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-007` only: B misses removal but receives re-add and still converges. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-007`: B misses removal but receives re-add and still converges. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-008
- source row id: `RA-008`
- scenario title: C misses removal but receives re-add and does not retain removed-window access
- source section: Remove and Re-add Regression Suite
- source line: `239`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-008` only: C misses removal but receives re-add and does not retain removed-window access. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-008`: C misses removal but receives re-add and does not retain removed-window access. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-009
- source row id: `RA-009`
- scenario title: First message sent by re-added member is visible to existing members
- source section: Remove and Re-add Regression Suite
- source line: `240`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-009` only: First message sent by re-added member is visible to existing members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-009`: First message sent by re-added member is visible to existing members. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-010
- source row id: `RA-010`
- scenario title: First incoming message to re-added member is visible before and after restart
- source section: Remove and Re-add Regression Suite
- source line: `241`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-010` only: First incoming message to re-added member is visible before and after restart. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-010`: First incoming message to re-added member is visible before and after restart. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-011
- source row id: `RA-011`
- scenario title: Immediate re-add before `group:leave` completes does not strand C
- source section: Remove and Re-add Regression Suite
- source line: `242`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-011` only: Immediate re-add before `group:leave` completes does not strand C. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-011`: Immediate re-add before `group:leave` completes does not strand C. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-012
- source row id: `RA-012`
- scenario title: Re-add same peer id with rotated device keys updates identity material
- source section: Remove and Re-add Regression Suite
- source line: `243`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-012` only: Re-add same peer id with rotated device keys updates identity material. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-012`: Re-add same peer id with rotated device keys updates identity material. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-014
- source row id: `RA-014`
- scenario title: Removed member sending with old key after re-add does not poison the group
- source section: Remove and Re-add Regression Suite
- source line: `245`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-014` only: Removed member sending with old key after re-add does not poison the group. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-014`: Removed member sending with old key after re-add does not poison the group. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-015
- source row id: `RA-015`
- scenario title: Go and Flutter config converge after `ALREADY_JOINED` on re-add
- source section: Remove and Re-add Regression Suite
- source line: `246`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-015` only: Go and Flutter config converge after `ALREADY_JOINED` on re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-015`: Go and Flutter config converge after `ALREADY_JOINED` on re-add. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-016
- source row id: `RA-016`
- scenario title: Delayed group inbox item from old removed interval is ignored after re-add
- source section: Remove and Re-add Regression Suite
- source line: `247`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-016` only: Delayed group inbox item from old removed interval is ignored after re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-016`: Delayed group inbox item from old removed interval is ignored after re-add. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-017
- source row id: `RA-017`
- scenario title: Every active member can still receive after C churn, not only C
- source section: Remove and Re-add Regression Suite
- source line: `248`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-017-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-017` only: Every active member can still receive after C churn, not only C. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-017` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-017`: Every active member can still receive after C churn, not only C. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-017-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-017`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-018
- source row id: `RA-018`
- scenario title: Churn with alternating senders remains deterministic
- source section: Remove and Re-add Regression Suite
- source line: `249`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-018-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-018` only: Churn with alternating senders remains deterministic. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-018` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-018`: Churn with alternating senders remains deterministic. Required source gates: Unit=Recommended, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-018-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-018`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-001
- source row id: `NW-001`
- scenario title: Full-mesh online group delivery works without relay fallback
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `255`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-001` only: Full-mesh online group delivery works without relay fallback. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-001`: Full-mesh online group delivery works without relay fallback. Required source gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-002
- source row id: `NW-002`
- scenario title: Relay-only or circuit-routed peers receive group messages
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `256`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-002` only: Relay-only or circuit-routed peers receive group messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-002`: Relay-only or circuit-routed peers receive group messages. Required source gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Recommended, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-003
- source row id: `NW-003`
- scenario title: Partition during removal and re-add heals to latest state
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `257`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-003` only: Partition during removal and re-add heals to latest state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-003`: Partition during removal and re-add heals to latest state. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-004
- source row id: `NW-004`
- scenario title: Relay reconnect preserves or repairs group topic subscriptions
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `258`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-004` only: Relay reconnect preserves or repairs group topic subscriptions. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-004`: Relay reconnect preserves or repairs group topic subscriptions. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-006
- source row id: `NW-006`
- scenario title: Peer disconnect does not equal group removal
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `260`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-006` only: Peer disconnect does not equal group removal. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-006`: Peer disconnect does not equal group removal. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-007
- source row id: `NW-007`
- scenario title: Topic peer count zero does not clear member list or disable recovery
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `261`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-007` only: Topic peer count zero does not clear member list or disable recovery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-007`: Topic peer count zero does not clear member list or disable recovery. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-010
- source row id: `NW-010`
- scenario title: Mobile background pause and foreground resume preserve group delivery
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `264`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-010` only: Mobile background pause and foreground resume preserve group delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-010`: Mobile background pause and foreground resume preserve group delivery. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-011
- source row id: `NW-011`
- scenario title: Send during background or app unmount is either durable or blocked
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `265`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-011` only: Send during background or app unmount is either durable or blocked. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-011`: Send during background or app unmount is either durable or blocked. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-012
- source row id: `NW-012`
- scenario title: Long offline reconnect with multiple epoch changes converges
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `266`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-012` only: Long offline reconnect with multiple epoch changes converges. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-012`: Long offline reconnect with multiple epoch changes converges. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-013
- source row id: `NW-013`
- scenario title: Stop/start during key rotation does not fork epochs
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `267`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-013` only: Stop/start during key rotation does not fork epochs. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-013`: Stop/start during key rotation does not fork epochs. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-014
- source row id: `NW-014`
- scenario title: Flaky network chaos run maintains model invariants
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `268`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-014` only: Flaky network chaos run maintains model invariants. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-014`: Flaky network chaos run maintains model invariants. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-002
- source row id: `PL-002`
- scenario title: Media-only group message is allowed when text is empty
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `276`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-002-plan.md`
- exact scope: Add row-specific regression proof for source row `PL-002` only: Media-only group message is allowed when text is empty. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-002`: Media-only group message is allowed when text is empty. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-005
- source row id: `PL-005`
- scenario title: Media allowedPeers match active membership at upload time
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `279`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-005` only: Media allowedPeers match active membership at upload time. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-005`: Media allowedPeers match active membership at upload time. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-006
- source row id: `PL-006`
- scenario title: Removed member cannot download media uploaded after removal
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `280`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-006` only: Removed member cannot download media uploaded after removal. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-006`: Removed member cannot download media uploaded after removal. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-007
- source row id: `PL-007`
- scenario title: Re-added member can download only post-readd media
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `281`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-007` only: Re-added member can download only post-readd media. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-007`: Re-added member can download only post-readd media. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-010
- source row id: `PL-010`
- scenario title: Removed member reaction is rejected and does not mutate visible state
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `284`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-010` only: Removed member reaction is rejected and does not mutate visible state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-010`: Removed member reaction is rejected and does not mutate visible state. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-014
- source row id: `PL-014`
- scenario title: Media and blob metadata never leak group keys or plaintext
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `288`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-014` only: Media and blob metadata never leak group keys or plaintext. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-014`: Media and blob metadata never leak group keys or plaintext. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-001
- source row id: `UP-001`
- scenario title: Member list, local DB, and Go config stay in sync after every operation
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `294`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-001` only: Member list, local DB, and Go config stay in sync after every operation. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-001`: Member list, local DB, and Go config stay in sync after every operation. Required source gates: Unit=Required, Integration=Required, Smoke=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-003
- source row id: `UP-003`
- scenario title: Compose box is enabled only for active members with current key
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `296`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-003` only: Compose box is enabled only for active members with current key. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-003`: Compose box is enabled only for active members with current key. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-005
- source row id: `UP-005`
- scenario title: Pending or failed invite state is visibly different from active member state
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `298`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-005` only: Pending or failed invite state is visibly different from active member state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-005`: Pending or failed invite state is visibly different from active member state. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-007
- source row id: `UP-007`
- scenario title: No native bridge call is made while holding a DB write transaction
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `300`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-007-plan.md`
- exact scope: Add row-specific regression proof for source row `UP-007` only: No native bridge call is made while holding a DB write transaction. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-007`: No native bridge call is made while holding a DB write transaction. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-008
- source row id: `UP-008`
- scenario title: Pending outbound group message survives restart and reconciles
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `301`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-008` only: Pending outbound group message survives restart and reconciles. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-008`: Pending outbound group message survives restart and reconciles. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-012
- source row id: `UP-012`
- scenario title: Removed member receives no notifications for post-removal messages
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `305`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-012` only: Removed member receives no notifications for post-removal messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-012`: Removed member receives no notifications for post-removal messages. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-013
- source row id: `UP-013`
- scenario title: Group route change or widget unmount does not drop incoming events
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `306`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-013` only: Group route change or widget unmount does not drop incoming events. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-013`: Group route change or widget unmount does not drop incoming events. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-001
- source row id: `SV-001`
- scenario title: Never-member cannot publish to private group
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `313`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-001` only: Never-member cannot publish to private group. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-001`: Never-member cannot publish to private group. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-002
- source row id: `SV-002`
- scenario title: Removed member cannot publish with old key
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `314`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-002` only: Removed member cannot publish with old key. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-002`: Removed member cannot publish with old key. Required source gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-003
- source row id: `SV-003`
- scenario title: Re-added member cannot publish until current key/config is installed
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `315`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-003` only: Re-added member cannot publish until current key/config is installed. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-003`: Re-added member cannot publish until current key/config is installed. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-004
- source row id: `SV-004`
- scenario title: Forged sender identity or signature is rejected
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `316`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-004` only: Forged sender identity or signature is rejected. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-004`: Forged sender identity or signature is rejected. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-005
- source row id: `SV-005`
- scenario title: Tampered ciphertext or nonce is rejected without stream poisoning
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `317`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-005` only: Tampered ciphertext or nonce is rejected without stream poisoning. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-005`: Tampered ciphertext or nonce is rejected without stream poisoning. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-006
- source row id: `SV-006`
- scenario title: Replay attack of an old valid message is deduped or rejected
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `318`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-006` only: Replay attack of an old valid message is deduped or rejected. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-006`: Replay attack of an old valid message is deduped or rejected. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-007
- source row id: `SV-007`
- scenario title: Wrong group id or topic mismatch is rejected
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `319`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-007` only: Wrong group id or topic mismatch is rejected. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-007`: Wrong group id or topic mismatch is rejected. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-008
- source row id: `SV-008`
- scenario title: Unauthorized config update cannot be applied from network payload
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `320`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-008` only: Unauthorized config update cannot be applied from network payload. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-008`: Unauthorized config update cannot be applied from network payload. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-009
- source row id: `SV-009`
- scenario title: Invalid member public keys are rejected during add or join
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `321`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-009` only: Invalid member public keys are rejected during add or join. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-009`: Invalid member public keys are rejected during add or join. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-010
- source row id: `SV-010`
- scenario title: Duplicate message ids from different senders cannot overwrite valid rows
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `322`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-010` only: Duplicate message ids from different senders cannot overwrite valid rows. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-010`: Duplicate message ids from different senders cannot overwrite valid rows. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-011
- source row id: `SV-011`
- scenario title: Valid key but nonmember sender is rejected
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `323`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-011` only: Valid key but nonmember sender is rejected. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-011`: Valid key but nonmember sender is rejected. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-013
- source row id: `SV-013`
- scenario title: Logs and diagnostics never expose group keys or plaintext
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `325`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-013` only: Logs and diagnostics never expose group keys or plaintext. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-013`: Logs and diagnostics never expose group keys or plaintext. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-016
- source row id: `SV-016`
- scenario title: Bridge keygen failure does not throw an unclassified field access error
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `328`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-016` only: Bridge keygen failure does not throw an unclassified field access error. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-016`: Bridge keygen failure does not throw an unclassified field access error. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-002
- source row id: `OB-002`
- scenario title: Diagnostics include group id prefix, key epoch, message id, and membership operation id where safe
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `335`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-002` only: Diagnostics include group id prefix, key epoch, message id, and membership operation id where safe. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-002`: Diagnostics include group id prefix, key epoch, message id, and membership operation id where safe. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-004
- source row id: `OB-004`
- scenario title: Decryption failure diagnostics trigger key repair workflow
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `337`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-004` only: Decryption failure diagnostics trigger key repair workflow. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-004`: Decryption failure diagnostics trigger key repair workflow. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-006
- source row id: `OB-006`
- scenario title: Dispatcher pressure and overflow are logged and tied to recovery
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `339`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-006-plan.md`
- exact scope: Add row-specific regression proof for source row `OB-006` only: Dispatcher pressure and overflow are logged and tied to recovery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-006`: Dispatcher pressure and overflow are logged and tied to recovery. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-007
- source row id: `OB-007`
- scenario title: EventChannel error or done produces a health failure or reinit attempt
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `340`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-007` only: EventChannel error or done produces a health failure or reinit attempt. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-007`: EventChannel error or done produces a health failure or reinit attempt. Required source gates: Unit=Required, Integration=Required, Smoke=Recommended.
- likely named gates: Unit=Required, Integration=Required, Smoke=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-008
- source row id: `OB-008`
- scenario title: Retry job ownership is unambiguous for each degraded branch
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `341`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-008` only: Retry job ownership is unambiguous for each degraded branch. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-008`: Retry job ownership is unambiguous for each degraded branch. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-011
- source row id: `OB-011`
- scenario title: Release telemetry can answer who missed which message and why
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `344`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-011` only: Release telemetry can answer who missed which message and why. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-011`: Release telemetry can answer who missed which message and why. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-012
- source row id: `OB-012`
- scenario title: Sensitive diagnostic redaction is tested with real-looking secrets
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `345`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-012` only: Sensitive diagnostic redaction is tested with real-looking secrets. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-012`: Sensitive diagnostic redaction is tested with real-looking secrets. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-001
- source row id: `ST-001`
- scenario title: Model-based membership state machine verifies every message recipient set
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `351`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-001` only: Model-based membership state machine verifies every message recipient set. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-001`: Model-based membership state machine verifies every message recipient set. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-002
- source row id: `ST-002`
- scenario title: Permutation test for add, remove, key, config, and message event ordering
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `352`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-002` only: Permutation test for add, remove, key, config, and message event ordering. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-002`: Permutation test for add, remove, key, config, and message event ordering. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-003
- source row id: `ST-003`
- scenario title: Epoch monotonicity property test
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `353`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-003` only: Epoch monotonicity property test. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-003`: Epoch monotonicity property test. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-005
- source row id: `ST-005`
- scenario title: High-throughput event storm does not lose messages without recovery
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `355`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-005` only: High-throughput event storm does not lose messages without recovery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-005`: High-throughput event storm does not lose messages without recovery. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-006
- source row id: `ST-006`
- scenario title: Concurrent publishes during key rotation remain visible to active members
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `356`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-006` only: Concurrent publishes during key rotation remain visible to active members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-006`: Concurrent publishes during key rotation remain visible to active members. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-007
- source row id: `ST-007`
- scenario title: Process death at every step of add, remove, and re-add recovers safely
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `357`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-007-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-007` only: Process death at every step of add, remove, and re-add recovers safely. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-007` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-007`: Process death at every step of add, remove, and re-add recovers safely. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-007-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-007`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-008
- source row id: `ST-008`
- scenario title: DB lock contention does not delay bridge event handling into message loss
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `358`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-008` only: DB lock contention does not delay bridge event handling into message loss. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-008`: DB lock contention does not delay bridge event handling into message loss. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-011
- source row id: `ST-011`
- scenario title: Rapid EventChannel reinitialize loop does not drop group callbacks permanently
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `361`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-011` only: Rapid EventChannel reinitialize loop does not drop group callbacks permanently. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-011`: Rapid EventChannel reinitialize loop does not drop group callbacks permanently. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-013
- source row id: `ST-013`
- scenario title: Relay chaos with store, retrieve, cursor, and repair failures
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `363`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-013` only: Relay chaos with store, retrieve, cursor, and repair failures. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-013`: Relay chaos with store, retrieve, cursor, and repair failures. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-014
- source row id: `ST-014`
- scenario title: Long soak test with membership churn and periodic restarts
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `364`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-014` only: Long soak test with membership churn and periodic restarts. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-014`: Long soak test with membership churn and periodic restarts. Required source gates: Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-005
- source row id: `BB-005`
- scenario title: Unsupported group types are rejected without partial state
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `113`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-005-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-005` only: Unsupported group types are rejected without partial state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-005`: Unsupported group types are rejected without partial state. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-014
- source row id: `BB-014`
- scenario title: GoBridge command map covers every private-group command used by helpers
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `122`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-014-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-014` only: GoBridge command map covers every private-group command used by helpers. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-014`: GoBridge command map covers every private-group command used by helpers. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-015
- source row id: `BB-015`
- scenario title: Native null, missing plugin, platform error, and malformed JSON responses are safe
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `123`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-015-plan.md`
- exact scope: Add row-specific regression proof for source row `BB-015` only: Native null, missing plugin, platform error, and malformed JSON responses are safe. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-015`: Native null, missing plugin, platform error, and malformed JSON responses are safe. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session BB-016
- source row id: `BB-016`
- scenario title: Description or extra metadata fields do not cause Dart/Go config drift
- source section: Bootstrap, Bridge Contract, and Topic-State Truth
- source line: `124`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `BB-016` only: Description or extra metadata fields do not cause Dart/Go config drift. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`.
- likely code-entry files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/events.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/media.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/join_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`
- likely direct tests or regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plus any row-specific test named for `BB-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `BB-016`: Description or extra metadata fields do not cause Dart/Go config drift. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-010
- source row id: `ML-010`
- scenario title: Duplicate add is idempotent and does not duplicate members or keys
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `139`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-010` only: Duplicate add is idempotent and does not duplicate members or keys. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-010`: Duplicate add is idempotent and does not duplicate members or keys. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-012
- source row id: `ML-012`
- scenario title: Concurrent admin membership edits resolve deterministically
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `141`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-012` only: Concurrent admin membership edits resolve deterministically. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-012`: Concurrent admin membership edits resolve deterministically. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-016
- source row id: `ML-016`
- scenario title: New member with no social-graph friendship still receives and renders messages
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `145`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-016` only: New member with no social-graph friendship still receives and renders messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-016`: New member with no social-graph friendship still receives and renders messages. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ML-020
- source row id: `ML-020`
- scenario title: Group creator or admin role changes do not break private delivery
- source section: Membership Lifecycle, Config Convergence, and Human-Visible Truth
- source line: `149`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-020-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ML-020` only: Group creator or admin role changes do not break private delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/core/database/helpers/group_members_db_helpers.dart`
- likely direct tests or regressions: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `ML-020` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ML-020`: Group creator or admin role changes do not break private delivery. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-020-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-020`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-004
- source row id: `KE-004`
- scenario title: Same-epoch same-key `updateKey` is idempotent
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `158`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-004` only: Same-epoch same-key `updateKey` is idempotent. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-004`: Same-epoch same-key `updateKey` is idempotent. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session KE-022
- source row id: `KE-022`
- scenario title: Key update errors are visible in diagnostics and recovery UI
- source section: Key Epoch, Rotation, and Stale-State Safety
- source line: `176`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-022-plan.md`
- exact scope: Implement and prove the exact row contract for source row `KE-022` only: Key update errors are visible in diagnostics and recovery UI. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`.
- likely code-entry files: `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/rotate_group_key_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_key_update_signature.dart`, `lib/features/groups/domain/models/group_key_info.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `go-mknoon/crypto/group.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`, `test/features/groups/application/rotate_group_key_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `go-mknoon/crypto/group_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` plus any row-specific test named for `KE-022` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `KE-022`: Key update errors are visible in diagnostics and recovery UI. Required source gates: Unit=Required, Integration=Required, Fake Network=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-022-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `KE-022`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-010
- source row id: `DE-010`
- scenario title: Native callback panic does not kill the Go dispatcher loop
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `191`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-010-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-010` only: Native callback panic does not kill the Go dispatcher loop. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-010`: Native callback panic does not kill the Go dispatcher loop. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-015
- source row id: `DE-015`
- scenario title: Payload parse failure does not poison the group stream
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `196`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-015-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-015` only: Payload parse failure does not poison the group stream. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-015`: Payload parse failure does not poison the group stream. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-016
- source row id: `DE-016`
- scenario title: Validation rejection is surfaced to diagnostics
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `197`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-016-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-016` only: Validation rejection is surfaced to diagnostics. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-016`: Validation rejection is surfaced to diagnostics. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-020
- source row id: `DE-020`
- scenario title: Large message payloads do not starve the event dispatcher
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `201`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-020-plan.md`
- exact scope: Implement and prove the exact row contract for source row `DE-020` only: Large message payloads do not starve the event dispatcher. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-020` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-020`: Large message payloads do not starve the event dispatcher. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-020-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-020`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-003
- source row id: `IR-003`
- scenario title: Timestamp-based retrieval has no boundary skips or duplicates
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `209`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-003-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-003` only: Timestamp-based retrieval has no boundary skips or duplicates. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-003`: Timestamp-based retrieval has no boundary skips or duplicates. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-010
- source row id: `IR-010`
- scenario title: History gaps from cursor retrieval are parsed and surfaced
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `216`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-010-plan.md`
- exact scope: Add row-specific regression proof for source row `IR-010` only: History gaps from cursor retrieval are parsed and surfaced. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-010`: History gaps from cursor retrieval are parsed and surfaced. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-011
- source row id: `IR-011`
- scenario title: History repair range request validates gap identity and source peer
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `217`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-011-plan.md`
- exact scope: Add row-specific regression proof for source row `IR-011` only: History repair range request validates gap identity and source peer. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-011`: History repair range request validates gap identity and source peer. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-016
- source row id: `IR-016`
- scenario title: Long offline retention cutoff is explicit and does not look like message loss
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `222`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-016-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-016` only: Long offline retention cutoff is explicit and does not look like message loss. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-016` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-016`: Long offline retention cutoff is explicit and does not look like message loss. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-016-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-016`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session RA-013
- source row id: `RA-013`
- scenario title: Re-add same user with multiple devices has per-device truthful state
- source section: Remove and Re-add Regression Suite
- source line: `244`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-013-plan.md`
- exact scope: Implement and prove the exact row contract for source row `RA-013` only: Re-add same user with multiple devices has per-device truthful state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`.
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_real_crypto_onboarding_test.dart`, `integration_test/group_multi_party_device_real_harness.dart` plus any row-specific test named for `RA-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `RA-013`: Re-add same user with multiple devices has per-device truthful state. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `RA-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-005
- source row id: `NW-005`
- scenario title: Rendezvous rediscovery after membership change does not affect membership truth
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `259`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-005-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-005` only: Rendezvous rediscovery after membership change does not affect membership truth. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-005`: Rendezvous rediscovery after membership change does not affect membership truth. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-008
- source row id: `NW-008`
- scenario title: Duplicate libp2p connections do not duplicate visible messages
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `262`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-008-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-008` only: Duplicate libp2p connections do not duplicate visible messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-008`: Duplicate libp2p connections do not duplicate visible messages. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-009
- source row id: `NW-009`
- scenario title: Relay probe failure does not remove or mute group members
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `263`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-009` only: Relay probe failure does not remove or mute group members. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-009`: Relay probe failure does not remove or mute group members. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session NW-015
- source row id: `NW-015`
- scenario title: Dial and disconnect commands cannot corrupt group topic state
- source section: Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle
- source line: `269`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `NW-015` only: Dial and disconnect commands cannot corrupt group topic state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go`.
- likely code-entry files: `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `go-mknoon/node/relay_session.go`, `go-mknoon/node/relay_selector.go`, `go-mknoon/node/group.go`
- likely direct tests or regressions: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/multi_relay_failover_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `go-mknoon/node/multi_relay_test.go` plus any row-specific test named for `NW-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `NW-015`: Dial and disconnect commands cannot corrupt group topic state. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `NW-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-001
- source row id: `PL-001`
- scenario title: Unicode and multiline text survives live and replay delivery
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `275`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-001-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-001` only: Unicode and multiline text survives live and replay delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-001`: Unicode and multiline text survives live and replay delivery. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-003
- source row id: `PL-003`
- scenario title: Empty text with no media is rejected without local ghost row
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `277`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-003-plan.md`
- exact scope: Add row-specific regression proof for source row `PL-003` only: Empty text with no media is rejected without local ghost row. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-003`: Empty text with no media is rejected without local ghost row. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-004
- source row id: `PL-004`
- scenario title: Quoted message id is preserved across live, replay, and re-add boundaries
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `278`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-004` only: Quoted message id is preserved across live, replay, and re-add boundaries. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-004`: Quoted message id is preserved across live, replay, and re-add boundaries. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-008
- source row id: `PL-008`
- scenario title: Media upload progress coalescing never drops group messages
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `282`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-008-plan.md`
- exact scope: Add row-specific regression proof for source row `PL-008` only: Media upload progress coalescing never drops group messages. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-008` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-008`: Media upload progress coalescing never drops group messages. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-008-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-008`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-009
- source row id: `PL-009`
- scenario title: Reaction from active member publishes and routes correctly
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `283`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-009-plan.md`
- exact scope: Add row-specific regression proof for source row `PL-009` only: Reaction from active member publishes and routes correctly. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-009`: Reaction from active member publishes and routes correctly. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-011
- source row id: `PL-011`
- scenario title: Re-added member reaction after current key update succeeds
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `285`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-011` only: Re-added member reaction after current key update succeeds. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-011`: Re-added member reaction after current key update succeeds. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-012
- source row id: `PL-012`
- scenario title: Voice, GIF, file, image, and video payload schemas survive bridge publish opts
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `286`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `PL-012` only: Voice, GIF, file, image, and video payload schemas survive bridge publish opts. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-012`: Voice, GIF, file, image, and video payload schemas survive bridge publish opts. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session PL-013
- source row id: `PL-013`
- scenario title: Partial media download cleans up local files and retries safely
- source section: Payload Variants, Media, Quotes, and Reactions
- source line: `287`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-013-plan.md`
- exact scope: Add row-specific regression proof for source row `PL-013` only: Partial media download cleans up local files and retries safely. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/media/group_media_integrity_policy.dart`, `lib/core/media/group_media_size_policy.dart`, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go` plus any row-specific test named for `PL-013` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `PL-013`: Partial media download cleans up local files and retries safely. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-013-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `PL-013`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-002
- source row id: `UP-002`
- scenario title: Timeline shows durable add, remove, and re-add events
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `295`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-002-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-002` only: Timeline shows durable add, remove, and re-add events. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-002` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-002`: Timeline shows durable add, remove, and re-add events. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-002-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-002`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-004
- source row id: `UP-004`
- scenario title: Unread counts update correctly through removal and re-add
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `297`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-004` only: Unread counts update correctly through removal and re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-004`: Unread counts update correctly through removal and re-add. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-006
- source row id: `UP-006`
- scenario title: Re-add banner or system row never reuses stale removed state
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `299`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-006-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-006` only: Re-add banner or system row never reuses stale removed state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-006` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-006`: Re-add banner or system row never reuses stale removed state. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-006-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-006`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-009
- source row id: `UP-009`
- scenario title: Username and sender identity render consistently after re-add
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `302`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-009` only: Username and sender identity render consistently after re-add. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-009`: Username and sender identity render consistently after re-add. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-010
- source row id: `UP-010`
- scenario title: Opening from notification routes to correct current group state
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `303`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-010` only: Opening from notification routes to correct current group state. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-010`: Opening from notification routes to correct current group state. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-011
- source row id: `UP-011`
- scenario title: Muted group suppresses notifications but not delivery
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `304`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-011-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-011` only: Muted group suppresses notifications but not delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-011` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-011`: Muted group suppresses notifications but not delivery. Required source gates: Unit=Required, Integration=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-011-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-011`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session UP-014
- source row id: `UP-014`
- scenario title: Removed or pending member cannot be selected as share target
- source section: Local Persistence, UI Truth, Notifications, and Route Behavior
- source line: `307`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `UP-014` only: Removed or pending member cannot be selected as share target. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`.
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/bridge/go_bridge_client.dart`
- likely direct tests or regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart` plus any row-specific test named for `UP-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `UP-014`: Removed or pending member cannot be selected as share target. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `UP-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-012
- source row id: `SV-012`
- scenario title: Peer id canonicalization prevents duplicate identity bypass
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `324`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-012` only: Peer id canonicalization prevents duplicate identity bypass. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-012`: Peer id canonicalization prevents duplicate identity bypass. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-014
- source row id: `SV-014`
- scenario title: Relay operator cannot infer membership events beyond allowed metadata
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `326`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-014-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-014` only: Relay operator cannot infer membership events beyond allowed metadata. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-014` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-014`: Relay operator cannot infer membership events beyond allowed metadata. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-014-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-014`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session SV-015
- source row id: `SV-015`
- scenario title: Bridge helper decrypt failure returns explicit error, not TypeError-like crash
- source section: Security, Authorization, Tamper Resistance, and Privacy
- source line: `327`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `SV-015` only: Bridge helper decrypt failure returns explicit error, not TypeError-like crash. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`.
- likely code-entry files: `go-mknoon/node/group.go`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/bridge_group_helpers.dart`
- likely direct tests or regressions: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/crypto/group_test.go`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart` plus any row-specific test named for `SV-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `SV-015`: Bridge helper decrypt failure returns explicit error, not TypeError-like crash. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `SV-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-001
- source row id: `OB-001`
- scenario title: Every group bridge command emits request, response, timing, and outcome flow events
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `334`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-001-plan.md`
- exact scope: Add row-specific regression proof for source row `OB-001` only: Every group bridge command emits request, response, timing, and outcome flow events. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-001` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-001`: Every group bridge command emits request, response, timing, and outcome flow events. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-001-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-001`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-003
- source row id: `OB-003`
- scenario title: Publish debug events explain zero peers, validator rejects, and fallback choices
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `336`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-003-plan.md`
- exact scope: Add row-specific regression proof for source row `OB-003` only: Publish debug events explain zero peers, validator rejects, and fallback choices. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-003` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-003`: Publish debug events explain zero peers, validator rejects, and fallback choices. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-003-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-003`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-005
- source row id: `OB-005`
- scenario title: Validation rejection is visible in Flutter diagnostics
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `338`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-005-plan.md`
- exact scope: Add row-specific regression proof for source row `OB-005` only: Validation rejection is visible in Flutter diagnostics. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-005` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-005`: Validation rejection is visible in Flutter diagnostics. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-005-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-005`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-010
- source row id: `OB-010`
- scenario title: Group callback exceptions are observable in tests
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `343`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-010-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-010` only: Group callback exceptions are observable in tests. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-010`: Group callback exceptions are observable in tests. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-004
- source row id: `ST-004`
- scenario title: Clock skew and timestamp fuzz for replay boundaries
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `354`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-004-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-004` only: Clock skew and timestamp fuzz for replay boundaries. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-004` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-004`: Clock skew and timestamp fuzz for replay boundaries. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-004-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-004`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-009
- source row id: `ST-009`
- scenario title: Maximum group size churn remains reliable
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `359`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-009` only: Maximum group size churn remains reliable. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-009`: Maximum group size churn remains reliable. Required source gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required, 3-Party E2E=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-010
- source row id: `ST-010`
- scenario title: Invalid JSON and malformed bridge payload fuzzing
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `360`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-010-plan.md`
- exact scope: Add row-specific regression proof for source row `ST-010` only: Invalid JSON and malformed bridge payload fuzzing. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-010` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-010`: Invalid JSON and malformed bridge payload fuzzing. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-010-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-010`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-012
- source row id: `ST-012`
- scenario title: Topic subscription leak test after many churn cycles
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `362`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-012-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-012` only: Topic subscription leak test after many churn cycles. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-012` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-012`: Topic subscription leak test after many churn cycles. Required source gates: Unit=Required, Integration=Required.
- likely named gates: Unit=Required, Integration=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-012-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-012`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session ST-015
- source row id: `ST-015`
- scenario title: Seeded reproduction logs are stable enough for debugging
- source section: Stress, Fuzz, Model-Based, and Soak Tests
- source line: `365`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-015-plan.md`
- exact scope: Implement and prove the exact row contract for source row `ST-015` only: Seeded reproduction logs are stable enough for debugging. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `integration_test/relay_chaos_soak_test.dart`, `integration_test/group_recovery_e2e_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `ST-015` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `ST-015`: Seeded reproduction logs are stable enough for debugging. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-015-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ST-015`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session DE-018
- source row id: `DE-018`
- scenario title: Unknown group event type does not affect known event delivery
- source section: Message Publish, Receive, Event Dispatch, and Ordering
- source line: `199`
- source current status: `Partial`
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-018-plan.md`
- exact scope: Add row-specific regression proof for source row `DE-018` only: Unknown group event type does not affect known event delivery. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: tests only
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Partial, so nearby implementation or guard evidence exists but direct row proof is still missing. Nearby files/tests to inspect: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `go-mknoon/node/event_dispatcher.go`, `go-mknoon/bridge/events.go`
- likely direct tests or regressions: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/performance/benchmark_event_queue_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `DE-018` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `DE-018`: Unknown group event type does not affect known event delivery. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-018-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `DE-018`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session IR-020
- source row id: `IR-020`
- scenario title: Inbox repair cannot resurrect messages deleted by local policy as new unread items
- source section: Offline Inbox, Replay, Cursoring, and History Repair
- source line: `226`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-020-plan.md`
- exact scope: Implement and prove the exact row contract for source row `IR-020` only: Inbox repair cannot resurrect messages deleted by local policy as new unread items. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`.
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`
- likely direct tests or regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/drain_lock_window_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` plus any row-specific test named for `IR-020` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `IR-020`: Inbox repair cannot resurrect messages deleted by local policy as new unread items. Required source gates: Unit=Required, Integration=Required, Fake Network=Required.
- likely named gates: Unit=Required, Integration=Required, Fake Network=Required
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-020-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `IR-020`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

### Session OB-009
- source row id: `OB-009`
- scenario title: Unknown or malformed native events are counted and sanitized
- source section: Diagnostics, Observability, and Failure Attribution
- source line: `342`
- source current status: `Open`
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-009-plan.md`
- exact scope: Implement and prove the exact row contract for source row `OB-009` only: Unknown or malformed native events are counted and sanitized. Do not merge adjacent reliability, security, media, network, UI, or observability rows into this session.
- execution ownership: code changes and tests
- row evidence basis: No exact closure for this private-matrix source row id was found during lightweight inspection. The source marks the row Open, so nearby tests are supporting context only. Nearby files/tests to inspect: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go`.
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `go-mknoon/node/event_dispatcher.go`
- likely direct tests or regressions: `test/core/utils/flow_event_emitter_test.dart`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `go-mknoon/node/benchmark_event_queue_test.go` plus any row-specific test named for `OB-009` that the downstream plan adds.
- likely missing tests: Row-specific direct proof for `OB-009`: Unknown or malformed native events are counted and sanitized. Required source gates: Unit=Required, Integration=Recommended.
- likely named gates: Unit=Required, Integration=Recommended
- dependency on earlier sessions: none
- row dependencies / blockers: no decomposition-time dependency; if a downstream implementation plan discovers a missing row-local harness, raw injection hook, or configured device/relay fixture, record it in `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-009-plan.md` without dropping row ownership.
- matrix or closure docs to update when done: `Private_group_chat_reliability_test_matrix_full_with_rules.md` row `OB-009`; `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` when new or clarified proof lands.

## Downstream Execution Path

- intended downstream tool: `$implementation-session-pipeline-orchestrator` can consume this row-granular `*-session-breakdown.md` artifact directly.
- plan creation rule: create the doc-scoped plan named in each ledger row, using `<source-stem>-session-<session-id>-plan.md`.
- execution order: run P0 sessions first in the order shown, then P1, then P2. Do not reorder lower-priority rows ahead of unresolved P0/P1 rows unless a later controller records a concrete dependency reason.
- row closure rule: a downstream session closes only its source row and must update the source matrix row status/evidence plus this breakdown ledger entry. Broad subsystem acceptance is insufficient.
- test/gate rule: use the source matrix gate columns as the minimum named gate contract for each row. If a gate is not runnable in the current environment, record the exact blocker and required fixture.
- no implementation was performed by this decomposition; no tests or gates were run.
