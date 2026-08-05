# 338 - Cross-Layer Direct-Send Deadline Contract

Status: implemented — owned causal and curated gates green; repository host closure remains red only on checkpoint-reproduced Plan 337 expectations
Type: Bug
Spec: UI-14-Conn-Type/go-libp2p-transport-assessment-review.md, R3
Classification: implementation-complete / documented host-closure exception
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-05 18:20 CEST | Evidence Collector | R3 roadmap; current chat/delete/retry orchestration; Dart bridge; Go config, rendezvous, dial, stream-open/recovery/send; tests and gates | Confirmed 1.5-2 second ordinary live-send allowances versus a two-second receiver commit wait, fresh Dart phase clocks, renewed Go command budgets, and incomplete stream cleanup | Define one bounded contract without a combined API or cancellation protocol |
| 2026-08-05 18:42 CEST | Planner | Every `sendMessageWithReply`, `callP2PMessageSend`, `openChatStreamForSend`, and `recoverPeerForSend` caller; existing R2 implementation | Ordinary chat/delete and failed-delete replay are the coherent Dart scope; the shared Go command must preserve two-second immediate-ACK introductions and default-budget contact/reaction traffic | Pin type-scoped ACK reserve, bypass sentinels, and deterministic seams |
| 2026-08-05 18:55 CEST | Planner | Existing timing constants, telemetry fields, FDC budget tests, synthetic Go host-tail registration | No production percentile artifact justifies changing the six-second leg; retain it, add a three-second ACK reserve and existing 500 ms bridge margin, and allocate from remaining T0 time | Write causal Test Contract and submit it to independent review |
| 2026-08-05 19:28 CEST | Independent Reviewers | Full draft against Dart adapters, millisecond bridge serialization, Go recovery/rendezvous loops, stream lifecycle, existing native tests, and gate registration | Initial verdict `plan-fixes-required`: the direction was sound, but fresh-clock mutations, zero/floored budgets, rendezvous I/O deadlines, post-open expiry, both post-write deadline branches, close failure, and executable native RED staging needed stronger proof | Apply only the bounded plan deltas; do not widen R3 into cancellation, protocol, or transport redesign |
| 2026-08-05 19:47 CEST | Planner / Reviewer | Revised Scope Contract, TC-338-01/02/04/05/09/11/12/13/14/15/16, steps, gates, and blind spots | Every material review finding is now causal or explicitly preserved; tests-only `SendMessageWithTimeout`, synchronous `ClosePeer`, and rendezvous lifecycle are deliberately kept narrow | Verdict `ready`; hand off the reviewed plan for RED execution |

## Problem And Evidence

- Behavior to improve: an ordinary 1:1 text/media envelope or delete tombstone must have enough bounded time to receive the current deferred committed ACK, while discovery, dial, recovery, candidate failover, stream I/O, and Dart bridge waits all consume one coherent deadline rather than restarting a full timeout.
- Impact: valid receiver commitments can currently be classified as late; a failed reuse/discovery/recovery path can multiply latency by renewing budgets; and a Dart timeout can stop observing a native operation that still has fresh internal time to open and write the envelope.
- Confirmed root causes/current gaps:
  - receiver commitment may wait `DirectConfirmTimeout = 2s` at `go-mknoon/node/config.go:90-95` and `go-mknoon/node/node.go:1851-1884`, while chat reuse/sticky receives 2 seconds and cold-direct/live-relay receives 1.5 seconds at `lib/features/conversation/application/send_chat_message_use_case.dart:756-771,1689-1705,1832-1851,1994-2005`;
  - `sendChatMessage` starts a monotonic-looking stopwatch at entry (`:291`) but the six-second direct wrapper begins only when the race is assembled (`:1119-1139`), and discover/dial/send each receive fresh 2s/1.5s/1.5s caps (`:1948-2005`);
  - delete reuse requests 2 seconds, its whole direct future is separately cut at 2 seconds, and discover/dial/send each receive another 2 seconds at `lib/features/conversation/application/delete_message_use_case.dart:451-505,1053-1087`; relay recovery then starts fresh dial/send caps at `:1089-1128`;
  - failed-delete replay requests only 2 seconds after inbox failure at `lib/features/conversation/application/retry_failed_messages_use_case.dart:903-946`;
  - `callP2PMessageSend` already has a correct native-budget-plus-500-ms watchdog at `lib/core/bridge/p2p_bridge_client.dart:1429-1459`, but rendezvous discovery and explicit dial have no equivalent bridge watchdog at `:553-588,607-639`, while several use-case wrappers fire at exactly the native deadline;
  - Dart serializes `Duration.inMilliseconds`, while Go interprets `timeoutMs <= 0` as a fresh default timeout at `go-mknoon/node/node.go:1620-1623` and `go-mknoon/node/rendezvous.go:127-130`; a sub-millisecond remaining phase must therefore be rejected before the bridge, and committed-send admission must use the serialized/floored millisecond value;
  - `SendMessageWithTransport` derives one timeout but `openChatStreamForSend` gives each open attempt a new context, recovery receives the full duration, retry opens with a fresh context, and established stream I/O receives `time.Now().Add(timeout)` at `go-mknoon/node/node.go:1519-1563,1606-1651`;
  - relay self-heal renews the duration for every relay/address candidate at `node.go:1427-1474`, and rendezvous discovery creates a fresh timeout plus a second `now + timeout` stream-I/O deadline inside every candidate callback at `go-mknoon/node/rendezvous.go:127-172`;
  - the bridge-used send path uses unconditional `defer s.Close()` and never calls `CloseWrite`; write or ACK-read failure therefore closes normally instead of resetting at `node.go:1625-1652`.
- Existing coverage:
  - Plan 336's atomic outgoing settlement and Plan 337's proof-aware first authenticated commitment are present in current source/tests; R3 may lengthen observation without reintroducing winner grace or stale persistence.
  - `test/core/bridge/p2p_bridge_client_test.dart:1017-1067` proves message timeout forwarding and the existing `timeoutMs + 500ms` watchdog, although its old RED comment is now stale.
  - `go-mknoon/node/send_message_recovery_test.go` proves retryable/non-retryable self-heal, limited-connection context, and ACK parsing; `go-mknoon/node/multi_relay_test.go::TestRendezvousDiscover_TriesSecondRelayWhenFirstFails` proves failover but not one shared deadline.
  - `send_message_recovery_test.go::TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat` currently gives a deferred chat only 500 ms; R3 must retime that fixture above the new three-second reserve while keeping its 50 ms receiver override and uncommitted assertion.
  - `DialPeerWithTimeout` already uses one `context.WithTimeout` around one `h.Connect` at `go-mknoon/node/node.go:1340-1379`; this is a GREEN preservation contract, not a production rewrite target.
- Missing coverage: no deterministic test pins T0 before envelope preparation, remaining-budget phase admission, one absolute deadline through recovery/candidates, a type-scoped three-second ACK reserve, post-write ACK timing, discover/dial watchdog ordering, or outcome-specific `CloseWrite`/`Close`/`Reset` behavior.
- Refuted findings:
  - the explicit-timeout `message:send` bridge wait is not unbounded; its existing 500 ms looser watchdog must be reused rather than rebuilt.
  - explicit Go dial does not currently renew its budget; changing it is unnecessary.
  - a universal pre-write reserve is unsafe: introduction sends use a two-second budget at `lib/features/introduction/application/introduction_outbound_delivery.dart:297-303,522-555,580-595`, and `shouldDeferDirectAck` deliberately treats introduction as immediate-ACK at `go-mknoon/node/node.go:1735-1751`.
- Unresolved finding / bounded decision: no checked-in production percentile artifact was found for `discoverMs`, `dialMs`, `streamOpenMs`, `writeMs`, or `ackWaitMs`. R3 therefore retains the existing six-second direct-leg ceiling instead of making a speculative latency retime. Later telemetry may tune that value without changing the timer anchors.
- Principal affected production files:
  - `lib/features/conversation/application/outgoing_live_deadline.dart` (new small allocator)
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/delete_message_use_case.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/rendezvous.go`
- Principal test/gate files:
  - `test/features/conversation/application/outgoing_live_deadline_test.dart` (new)
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/application/delete_message_use_case_test.dart`
  - `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - `test/core/bridge/p2p_bridge_client_test.dart`
  - `test/performance/send_path_budget_hard_gate_test.dart`
  - `go-mknoon/node/deadline_contract_test.go` (new)
  - `go-mknoon/node/config_test.go`
  - `go-mknoon/node/send_message_recovery_test.go`
  - `go-mknoon/node/multi_relay_test.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `scripts/run_host_test_gates.sh`
  - `scripts/run_test_gates.sh`
  - `scripts/test/host_test_gate_batch_contract_test.sh`

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `8fa9b99b47ec3416`; `confidence=anchored`, with `go-mknoon/node/node.go` reported stale and every native linchpin re-verified directly in current source.
- Query / profile: `python3 graphify-arch/tdd_context.py query "R3 cross-layer deadline contract interactiveDirectAggregateBudget kDirectDiscoverBudget kDirectDialBudget kDirectSendBudget sendStopwatch sendMessageWithReply callP2PMessageSend SendMessageWithTransport openChatStreamForSend RendezvousDiscoverWithTimeout GO_NODE_LIBP2P_REFACTOR_RUN tests gates" --profile tdd --budget 700`.
- Anchors:
  - `interactiveDirectAggregateBudget` / `kDirectSendBudget` -> `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `callP2PMessageSend` -> `lib/core/bridge/p2p_bridge_client.dart:1408`
  - `SendMessageWithTransport` / `openChatStreamForSend` -> `go-mknoon/node/node.go`
  - `GO_NODE_LIBP2P_REFACTOR_RUN` -> `scripts/run_host_test_gates.sh:208`
- Surfaced proof/gate files: chat/delete use-case tests, `p2p_bridge_client_test.dart`, `send_message_recovery_test.go`, `run_test_gates.sh`, and `run_host_test_gates.sh`.
- Graph gaps requiring source search: current native deadline renewal, rendezvous candidate iteration, immediate-ACK callers, failed-delete replay, and batch-contract sentinel placement were all verified directly.
- Reuse rule: these anchors may be handed to execution/review; every conclusion remains grounded in current source or a named command.

## Scope Contract And Guard

In scope:

- Keep these concrete initial Dart values:

  ```text
  ordinary direct-leg deadline from T0:  6.0 seconds
  committed-ACK reserve:                 3.0 seconds
  bridge watchdog margin:                0.5 seconds
  maximum native message-send allocation at T0:
                                           5.5 seconds
  discover native phase cap:             2.0 seconds
  explicit dial native phase cap:        1.5 seconds
  local WebSocket budget:                unchanged at 1.5 seconds
  ```

- Add one small `OutgoingLiveDeadline` allocator shared by ordinary chat, initial delete, and failed-delete live replay. It consumes an injected elapsed-time reader; production binds that reader to `clock.stopwatch()` so it is monotonic in production and virtualizable by `fakeAsync` without adding a clock argument to public send APIs.
- For discover/dial, allocate `min(phaseCap, remainingLeg - 500ms)`, serialize through `Duration.inMilliseconds`, and call the bridge only when the resulting `timeoutMs >= 1`; zero or a positive sub-millisecond remainder must not reach Go, where it would select a fresh default. For deferred-commit `message:send`, allocate `remainingLeg - 500ms` and call only when the serialized `timeoutMs > 3000`. Thus `3000ms` and `3000ms + 999us` are rejected, while `3001ms` is admitted. Its Dart watchdog is the serialized native allocation plus 500 ms and therefore cannot outlive the same T0 leg.
- Anchor chat and initial-delete deadlines at their existing use-case entry stopwatches, before envelope encryption/staging and before failed reuse/sticky work. A failed reuse, sticky, discover, dial, relay-probe, or send attempt may consume remaining time but may not create another six-second leg.
- Preserve failed-delete retry's existing inbox-first order. Only if custody fails, create one six-second live-fallback deadline at entry to that fallback; do not charge the preceding inbox attempt to a direct leg that did not yet exist.
- Apply the allocator to authenticated chat reuse, learned direct/relay sticky, cold direct, live relay, delete reuse/direct/relay recovery, and failed-delete replay. Keep local WebSocket outside this contract.
- Export one 500 ms bridge-watchdog constant from `p2p_bridge_client.dart`; use it for explicit-timeout message send, rendezvous discovery, and dial. On watchdog expiry, discovery returns `ok:false, peers:[], errorCode:BRIDGE_TIMEOUT`, dial returns `ok:false, connected:false, errorCode:BRIDGE_TIMEOUT`, and send keeps its existing `ok:false, sent:false` map. A null `timeoutMs` remains uncapped in Dart for unrelated legacy/default-budget callers.
- In Go, turn each supplied rendezvous-discovery, explicit-dial, and message-send budget into one command deadline. Explicit dial already conforms and is preserved. Rendezvous candidates share one context and install that exact absolute deadline on every opened stream; a deadline-installation failure resets that candidate. Message stream open, self-heal relay candidates, retry, complete frame write, half-close, and ACK read share one command deadline.
- Add a separate exact `CommittedAckReserve = 3s`; do not retime `InteractiveSendTimeout`, which is frozen by an older cold-start verdict and is used by group validation feedback.
- Replace the stale config relationship that describes `DirectConfirmTimeout` as fitting inside `InteractiveSendTimeout` with the actual `DirectConfirmTimeout < CommittedAckReserve` contract; keep the literal `InteractiveSendTimeout == 3s` cold-start lock green.
- Apply the pre-write reserve only when the outgoing envelope type is one whose current receiver defers ACK (`chat_message`, `message_reaction`, `message_deletion`, or `contact_request`). Parse/type failure and immediate-ACK types retain the full absolute command deadline. Reuse one pure envelope-type predicate with the receiver's deferred-ACK classification so sender and receiver cannot silently drift.
- For reserve-bearing sends, derive `preWriteDeadline = commandDeadline - 3s`. Open, self-heal, and retry must finish, and no write may start, after that cutoff; the write itself runs under the pre-write deadline. An open hook returning after its context expires is reset without a write. If an already-started write defensively races the deadline but nevertheless returns complete, treat the frame as written and clamp the next phase to `commandDeadline`. Immediately after every complete write, derive and install `ackDeadline = min(commandDeadline, writeCompletedAt + 3s)`, then call `CloseWrite` and read under that deadline. Immediate-ACK types use the same command deadline for open/write/half-close/read without the reserve split.
- Treat deadline installation as part of the bound: failure to install the pre-write deadline resets before writing; failure to install the post-write deadline, `CloseWrite`, or ACK read resets after a complete write and returns written/uncommitted evidence. A successful frame read (including valid `ack:false` or malformed/non-affirmative application data) closes normally; if normal `Close` fails, make one best-effort `Reset` without changing the already-derived reply/ACK result. Preserve `sent:true, acked:false` for every failure after the complete frame write; only pre-write/open/write failures are transport errors.
- Add only narrow context-aware internal variants/test seams for chat recovery and rendezvous stream opening. Keep duration-based wrappers where group feedback or public relay probing needs its existing independent behavior; do not redesign `RelaySelector`.
- Add a narrow absolute-deadline setter (or call `Stream.SetDeadline(absolute)` directly) only for R3 message-send and rendezvous-discovery paths. Leave the existing duration-based `setStreamDeadline` helper and its media/inbox/group/tests-only callers untouched.
- Keep `h.Network().ClosePeer(pid)` synchronous because that libp2p API has no context; R3 bounds every context/deadline-capable network attempt but does not add a goroutine watchdog around this local close.
- Limit chat `CloseWrite`/outcome-cleanup changes to `message:send`. Rendezvous keeps its current close-on-success/reset-on-error protocol lifecycle; R3 changes only its shared command context and absolute stream deadline.
- Extend the existing `GO_NODE_LIBP2P_REFACTOR_RUN` selector with `TestR3Deadline_` and the retimed `TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat`, and add batch-contract sentinels. Preserve the aggregate eight-Go-invocation host shape.

Must preserve:

- Plan 336 atomic status advancement and Plan 337 first authenticated committed settlement -> exact outgoing-settlement and R2 selector/delete/retry sentinels in TC-338-15.
- One-and-a-half-second local WebSocket cutoff and its unauthenticated/written authority -> `send_chat_message_use_case_test.dart::passes interactive local budget to the WiFi transport` and `::U5 budget: a slow local leg is cut at the local budget`.
- Relay staggering/ranking, direct/relay labels, and first-proof settlement -> existing FDC-02/R2 tests; only their obsolete independent-send-budget assertion/prose may be updated.
- Explicit dial's one-context implementation and bridge timeout forwarding -> TC-338-15.
- Immediate-ACK introduction remains admitted with a two-second budget; contact request/reaction default 15-second sends remain admitted and reserve-bearing; delivery receipts/posts/profile/control traffic keep their current feature ordering/status semantics -> TC-338-08/09/15.
- Self-heal eligibility, `WithAllowLimitedConn`, no-address recovery, and the tests-only `SendMessageWithTimeout` sibling remain operational -> TC-338-10/15. Adapt that sibling only where a shared helper signature requires it; do not broaden R3 into a second lifecycle/reserve rewrite without a causal test.
- Inbox-first failed-delete replay order, retained envelope on uncommitted send, private tombstone visibility, and delete cleanup remain unchanged -> TC-338-06/15.
- Native `sent:true, acked:false` on post-complete-write half-close/deadline/ACK-read failure remains unchanged even though the stream now resets -> TC-338-14.

Hard `Do not`:

- Do not add a combined discover/dial/send native API, coordinator, queue, address racer, streaming discovery pipeline, route scorer, or new ACK level/protocol.
- Do not add cross-FFI attempt IDs/cancellation, a native spool, a pending inbox state, goroutine-based close watchdog, or a general clock framework.
- Do not change presence ordering, inbox scheduling/hedge timing, attachment live-relay eligibility, relay stagger/ranking, DCUtR timing, resource-manager policy, or WebSocket authority/removal; R4/R5 or evidence-gated follow-ups own those decisions.
- Do not raise or repurpose the shared two-second `interactiveDirectBudget`; immediate-ACK introduction currently imports it.
- Do not enforce the three-second reserve on every opaque/immediate-ACK `message:send` frame.
- Do not add `CloseWrite` or a new result protocol to rendezvous streams, and do not wrap synchronous `ClosePeer` in a goroutine merely to simulate cancellation.
- Do not change deadline behavior for media, inbox, group-inbox, rendezvous register/unregister, or other users of the existing duration-based stream-deadline helper.
- Do not rewrite generic `RelaySelector`, unrelated contact/introduction/post/profile/delivery-receipt feature orchestration, or group validation feedback semantics.
- Do not introduce a DB/schema change, device requirement, public-relay campaign, or quantitative UX-performance claim.

Deferred / accepted difference:

- Cross-FFI cancellation -> evidence-gated follow-up only if telemetry after absolute deadlines shows meaningful native work surviving a Dart watchdog/platform suspension.
- Presence-independent custody hedge -> R4.
- Attachment-envelope live relay -> R5.
- Six-second leg retuning -> later telemetry decision using production percentiles; R3 intentionally keeps the current outer ceiling.
- Removal of WebSocket chat transport, foreground connection single-flight, DCUtR/resource policy, and discovery redesign -> roadmap conditional follow-ups.
- Mixed-version/force-disabled deferred ACK capability -> Plan 337's accepted current-version/default-on release assumption remains; R3 does not solve capability negotiation.
- Failed-delete replay begins its direct-leg clock only after its existing inbox-first attempt fails -> deliberate asymmetry because no live direct leg exists before then.

Dependencies:

- R1 / Plan 336 is implementation-complete and supplies atomic ordinary settlement.
- R2 / Plan 337 production and causal tests are present in current source; its plan/index bookkeeping still says execution-ready and is an administrative closure gap, not a technical R3 prerequisite.
- R3 closes the R1-R3 correctness dependency wave. Its individual gates run first; one aggregate `host-all` runs once afterward as wave closure.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-338-01 | One six-second T0 leg exposes remaining time, a three-second committed-ACK reserve, and a 500 ms watchdog margin without phase reset or millisecond-floor bypass | `test/features/conversation/application/outgoing_live_deadline_test.dart::R3 direct deadline uses one T0 remaining budget and exact reserve margins` | Dart host; pure allocator with mutable elapsed reader; boundary table at serialized `0/1ms` and raw `3000ms`, `3000ms+999us`, `3001ms`; no timers/network | HEAD has no shared allocator and uses fresh phase constants -> exact constants, decreasing remaining time, phase clamping, `nativeMs + 500 <= remainingMs`; phase calls require serialized `>=1`, while committed sends reject the first two 3s boundary rows and admit only `3001ms` | return the original total, admit floored zero, compare the higher-precision `Duration` before serialization, subtract no margin, or change a constant -> corresponding row red | `flutter test test/features/conversation/application/outgoing_live_deadline_test.dart`; add to both 1:1 arrays; AUTO feature/host globs |
| TC-338-02 | Chat reuse, learned direct/relay sticky, cold direct, and live relay all allow a valid ~2.2s committed ACK and use the original T0 after controlled pre-adapter work | `test/features/conversation/application/send_chat_message_use_case_test.dart::R3 committed ACK window is shared by reuse sticky cold direct and live relay` | Dart host; `fakeAsync`, existing P2P fake extended to honor/capture `timeoutMs`, table of five authenticated outcomes (reuse, sticky-direct, sticky-relay, cold-direct, live-relay) with non-zero controlled elapsed time before each adapter | HEAD passes 2s/2s/1.5s/1.5s and the honoring fake returns uncommitted/fallback -> every row settles `delivered`, records exactly `floor((6s - elapsedFromOriginalT0 - 500ms))`, and preserves route label/stagger scheduling | leave an adapter on its old constant, construct a fresh allocator in sticky/live-relay/direct, or restore exact-native `.timeout` -> its exact-budget/ACK row red | focused plain-name; existing `send_chat...` registration in both 1:1 arrays and feature auto-glob |
| TC-338-03 | T0 starts before envelope preparation, so preparation consuming the reserve prevents a later native write | `send_chat_message_use_case_test.dart::R3 T0 includes envelope preparation before live send admission` | Dart host; `fakeAsync`, `clock.stopwatch()`, controlled encryption/staging delay, authenticated direct fake and inbox fallback | HEAD starts the six-second wrapper after preparation and calls send with a fresh 1.5s -> after 2.5s controlled preparation, native allocation is not greater than reserve, `sendCallCount == 0`, and existing inbox/retryable result handles the message | start the deadline when race futures are assembled or create a new clock after encryption -> send unexpectedly fires | focused plain-name; existing test-file registration |
| TC-338-04 | Failed reuse and cold discover/dial phases consume the same T0 leg; later phases receive exact smaller budgets and cannot restart or default after exhaustion | `send_chat_message_use_case_test.dart::R3 failed reuse discovery and dial consume one T0 deadline` | Dart host; `fakeAsync`, timeout-capturing fake with controlled phase completion and exact call order; zero/sub-millisecond phase-exhaustion subcase | HEAD gives reuse and every later phase fresh budgets and reaches a second send -> each allocation equals `floor(min(cap, 6s - elapsedFromOriginalT0 - 500ms))`; after send budget serializes to `<=3000` no second send occurs, and after discover/dial serialize to `0` neither bridge call occurs | instantiate an allocator inside reuse/sticky/direct, pass a fixed phase constant, or forward zero to native -> exact timeout/call-count assertion red | focused plain-name; existing test-file registration |
| TC-338-05 | Initial delete reuse, cold direct, and relay-recovery send use one delete-entry T0 and exact progressively reduced allocations | `test/features/conversation/application/delete_message_use_case_test.dart::R3 delete reuse direct and relay share one committed ACK deadline` | Dart host; `fakeAsync`, existing controlled delete service extended to capture/honor timeouts; adapter table plus failed-reuse -> direct phases -> relay-recovery sequence | HEAD caps reuse/send at 2s and cold direct's entire future at 2s while phases renew -> each isolated adapter admits a 2.2s ACK, while the sequence records the exact T0-derived allocation at every call and never increases after elapsed work | leave an adapter on `interactiveDirectBudget`, recreate its 2s outer timeout, or construct a fresh allocator for relay recovery -> corresponding exact-budget/status row red | focused plain-name; existing delete registration in both 1:1 arrays and feature auto-glob |
| TC-338-06 | Failed-delete replay keeps inbox-first order, then gives its live fallback one bounded committed-ACK leg | `test/features/conversation/application/retry_failed_messages_use_case_test.dart::R3 failed delete replay reserves committed ACK after inbox failure` | Dart host; `fakeAsync`, existing R2 tombstone fixture with ordered inbox/send recorder and timeout-honoring ACK delay | HEAD's post-inbox live send passes 2s and misses a 2.2s commitment -> inbox is attempted first; after custody failure the one live call gets `>3s`, explicit ACK delivers/clears, and uncommitted still retains envelope | start live before inbox, reuse the expired inbox timer, or keep 2s -> ordering/budget/status assertion red | focused plain-name; existing `ONE_TO_ONE_TESTS`, feature/host auto-glob; run exact because absent from host 1:1 array |
| TC-338-07 | Explicit-timeout rendezvous, dial, and message bridge waits fire only at native budget + 500 ms and forward the unchanged native timeout | `test/core/bridge/p2p_bridge_client_test.dart::R3 explicit discover dial and send watchdogs are native budget plus margin` | Dart host; `fakeAsync`, hanging bridge table and captured request JSON | HEAD discover/dial never finish while message already has the correct margin -> at native deadline each remains pending; at +500 ms each returns its command-appropriate `BRIDGE_TIMEOUT` failure map, and payload timeout is unchanged | use native timeout exactly, add margin to payload, omit a command wrapper, or change margin -> table red | focused plain-name; existing bridge registration in both 1:1 arrays and core auto-glob |
| TC-338-08 | Native reserve is exactly 3s, exceeds the 2s receiver confirm window, and is limited to deferred-commit envelope types | `go-mknoon/node/deadline_contract_test.go::TestR3Deadline_CommitReserveExceedsReceiverAndIsTypeScoped`; corrected `go-mknoon/node/config_test.go::TestDirectConfirmTimeout_StaysWithinCommittedAckReserve` | Go host; pure type/constant table | HEAD has no separate reserve/type predicate and the old config test compares the wrong concepts -> `CommittedAckReserve == 3s`, `DirectConfirmTimeout < reserve`, and only chat/reaction/deletion/contact-request types require it | lower reserve to `<= DirectConfirmTimeout`, reuse the receiver feature-flag result, or classify introduction/receipt as deferred -> test red | direct R3 Go suite plus exact config selector; register R3 prefix in existing synthetic node leg |
| TC-338-09 | Deferred sends without a usable pre-write interval, including expiry during open, never write; immediate/default-budget siblings remain admitted | `deadline_contract_test.go::TestR3Deadline_PrewriteAdmissionIsTypeScoped` | Go host; pure `3000/3001ms` admission subtable; scripted stream/open rows use a comfortable admitted budget, two-second `introduction`, default-timeout contact/reaction, immediate receipt/control, plus `reserve+10ms` hook waiting on `ctx.Done()` before returning a stream | HEAD opens/writes a chat frame even at/beyond an expired cutoff -> `3000ms` rejects and `3001ms` admits without a 1 ms wall-clock race; the expiry-during-open stream resets with zero writes; introduction still completes at 2s; contact/reaction use default 15s reserve; immediate types use their full deadline | remove admission, check only before open, ignore `ctx.Err()` after open, apply reserve universally, or exempt contact/reaction -> corresponding row red | direct R3 Go suite; same synthetic registration; no long sleep (the hook waits on the 10 ms context) |
| TC-338-10 | First open, self-heal, and retry share the exact same pre-write deadline/context metadata | `deadline_contract_test.go::TestR3Deadline_MessageRecoveryReusesPrewriteDeadline` | Go host; existing open/recovery hooks changed narrowly to receive context; first open retryable, recovery success, second scripted stream | HEAD creates fresh contexts and passes a full duration to recovery -> all recorded `ctx.Deadline()` values become exactly equal, allow-limited remains set, and only one recovery occurs | call `context.WithTimeout` inside either attempt/recovery or drop limited-connection context -> equality/context assertion red | direct R3 Go suite; existing recovery selectors as preservation |
| TC-338-11 | Relay/address candidates used by message self-heal consume the same recovery context instead of renewing the supplied duration | `deadline_contract_test.go::TestR3Deadline_RelayRecoveryCandidatesShareDeadline` | Go host; narrow context-recording connect seam; table of one relay/two addresses and two relays/one address | HEAD creates `context.WithTimeout` inside each candidate -> every attempted candidate in both topologies observes the exact pre-write deadline; exhausted context stops before another useful attempt, with no new timeout | retain per-candidate `WithTimeout`, cover only one candidate dimension, or fall back to the duration wrapper -> deadline/count row red | direct R3 Go suite; same synthetic registration; do not assert incidental candidate timing beyond configured sequential order |
| TC-338-12 | Rendezvous discovery shares one absolute command deadline across relay/address failover for both stream open and I/O | `deadline_contract_test.go::TestR3Deadline_RendezvousCandidatesShareCommandDeadline` | Go host; narrow rendezvous-stream-open seam and scripted streams recording `SetDeadline`; table of one relay/two addresses and two relays/one address | HEAD creates per-candidate contexts and installs `now+timeout` on every stream -> each open context and stream deadline equals the outer command deadline; deadline-install failure resets/fails that candidate under existing failover, without renewal | move `WithTimeout` into the callback, restore duration-based `setStreamDeadline`, ignore deadline errors, or use the coarse hook that bypasses production logic -> row red | direct R3 Go suite; `multi_relay_test.go::TestRendezvousDiscover_TriesSecondRelayWhenFirstFails` preservation |
| TC-338-13 | After complete write, the ACK deadline is installed before `CloseWrite` and equals `min(commandDeadline, writeCompletedAt+3s)` on both formula branches | `deadline_contract_test.go::TestR3Deadline_PostWriteAckDeadlineAndOrder` | Go host; scripted clock/stream; ordinary early-write row where reserve caps, plus a defensive row where a write started before the cutoff races its deadline yet returns complete afterward so command deadline caps; records write completion, deadline, `CloseWrite`, read, close/reset | HEAD has no `CloseWrite` and resets to a fresh full timeout -> both reachable rows prove exact deadline identity and order `complete frame write -> SetDeadline(ackDeadline) -> CloseWrite -> ACK read -> Close` | always choose command deadline, always choose write+reserve, reject/forget a successfully completed race, install after `CloseWrite`, or renew from current time -> an independent row/order assertion red | direct R3 Go suite; same synthetic registration; use one send-local time seam/pure helper, not a general clock framework |
| TC-338-14 | Deadline installation and chat-stream cleanup are outcome-specific without changing written-but-unacked evidence | `deadline_contract_test.go::TestR3Deadline_StreamCleanupMatchesOutcome` | Go host; scripted-stream table: pre-write-deadline failure, write failure, post-write-deadline failure, `CloseWrite` failure, ACK-read failure, `ack:false`, affirmative ACK, and normal-`Close` failure after each readable result | HEAD ignores deadline errors and closes every opened stream -> pre-write failures reset/error before bytes; every post-write failure resets and returns nil Go error/`Acked:false`; readable frames close normally; a failed normal close gets exactly one reset fallback while preserving the readable result | restore `defer Close`, ignore either deadline error, reset on `ack:false`, omit close-failure fallback, or return a transport error after complete write -> corresponding row red | direct R3 Go suite; existing ACK parser test preservation |
| TC-338-15 | Existing explicit dial, deferred-chat uncommitted behavior, R1/R2 settlement, local cutoff, recovery, and failover remain intact | `go-mknoon/bridge/bridge_test.go::TestRendezvousDiscover_HonorsTimeoutMs`; `::TestDialPeer_HonorsTimeoutMs`; `go-mknoon/node/send_message_recovery_test.go::TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat`; `::TestSendMessage_RetriesChatStreamOpenAfterSelfHeal`; `::TestSendMessage_OpensChatStreamsWithAllowLimitedConnAndDialTimeout`; `::TestSendMessageWithTimeout_OpensChatStreamsWithAllowLimitedConnAndDialTimeout`; `send_chat_message_use_case_test.dart::R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky`; `::R2 first authenticated committed ACK settles before virtual transport grace`; `delete_message_use_case_test.dart::R2 delete reuse race and relay require explicit authenticated commitment`; `retry_failed_messages_use_case_test.dart::R2 failed delete retry requires explicit committed ACK`; Plan 336 settlement files | Host; source-backed explicit-dial inspection, real bridge parser/in-process libp2p hosts, existing Dart fakes/SQL helper | Retiming the existing deferred-chat fixture from 500 ms to `CommittedAckReserve + bounded margin` keeps its 50 ms receiver override and unacked result executable; all other named GREEN sentinels remain green after signature/context/timer changes | leave that fixture below/equal to reserve, drop forwarding/limited context, regress proof/local budget, or alter atomic persistence -> a named sentinel red | exact commands below; add the retimed deferred-chat sentinel to the existing Go synthetic selector; other registrations/auto-globs unchanged |
| TC-338-16 | The R3 Go suite and retimed deferred-chat sentinel are selected by the existing node synthetic leg without adding a ninth Go invocation | `scripts/test/host_test_gate_batch_contract_test.sh::TestR3Deadline_ and deferred-chat sentinels plus eight-leg shape` | Shell host; fake Flutter/Go command logs | HEAD selector/sentinels do not contain R3/deferred-chat preservation -> batch contract requires both selectors, still observes 8 Go calls, 4 node-package legs, and one existing libp2p-refactor invocation | omit either selector/sentinel or add a separate ninth Go leg -> script red | `bash scripts/test/host_test_gate_batch_contract_test.sh`; manual selector registration |

### Test Notes

- TC-338-02/03/04/05/06 use `fakeAsync`; production entry stopwatches must be created through `clock.stopwatch()` because a raw `Stopwatch()` is not virtualized. No public clock parameter is added.
- TC-338-07 must assert the future is incomplete at the native timeout and completes only after the 500 ms margin. The hanging bridge is never awaited outside `fakeAsync`, so no wall-clock sleep or runner-timeout RED is used.
- TC-338-10/11/12 compare exact `context.Deadline()` identity. TC-338-12 also records the stream's absolute deadline, so a context-only fix cannot leave renewed rendezvous I/O. None uses the coarse `rendezvousDiscoverHook`, which bypasses the production timeout loop.
- TC-338-13/14 use a scripted `network.Stream`; a readable but non-affirmative ACK is a completed protocol exchange and closes normally. Deadline/I/O/half-close failures reset, normal-close failure gets a reset fallback, and post-complete-write failures retain written/uncommitted outward evidence.

## Implementation Steps

1. Snapshot `git status --short`, `git diff --cached --name-status`, and the existing Plan 336/R2 dirty-tree ownership. Run the exact current recovery, failover, ACK parser, bridge-forwarding, and R1/R2 sentinels as the preservation baseline.
2. Before causal native tests, make one behavior-preserving observation-seam checkpoint: context-capable internal recovery/relay-connect hooks, a rendezvous stream-open seam that exposes `SetDeadline`, and one send-local time seam/pure deadline helper. Keep public duration wrappers and production behavior unchanged, and rerun the Step 1 native sentinels GREEN. This checkpoint makes TC-338-10/11/12/13 executable as runtime RED rather than impossible or vacuous compile failures.
3. Add TC-338-01 through TC-338-16 before contract-changing production edits; run every named RED and record selected causal failures. A missing new allocator/reserve symbol may briefly produce compile RED, but TC-338-10/11/12 must reach assertion RED through the seam checkpoint, and no zero-test/runner-timeout result counts.
4. Add `outgoing_live_deadline.dart` with only the shared constants, serialized-millisecond admission, allocation arithmetic, and elapsed-reader seam. Switch existing chat/delete entry timers to `clock.stopwatch()` and update test fakes to capture/honor direct `timeoutMs`. Stop-if: a public send API clock parameter or generalized scheduler appears necessary; rework the private helper instead.
5. Thread the one allocator through chat reuse, sticky, direct discovery/dial/send, and live relay. Replace fresh/equal wrappers with exact remaining-budget allocations; do not forward zero/floored phases. Keep local WebSocket budget and relay stagger unchanged. Stop-if: any implementation changes presence/inbox scheduling or route authority; those belong to R4/R2.
6. Apply the same allocator to initial delete reuse/direct/relay recovery and to the failed-delete live fallback after inbox-first failure. Preserve deletion settlement, tombstone visibility, cleanup, and inbox order.
7. Name/reuse the existing 500 ms bridge margin in `p2p_bridge_client.dart`; add null-safe explicit-timeout watchdogs for rendezvous and dial with command-appropriate failure maps. Do not cap null-timeout callers.
8. Add `CommittedAckReserve` and one pure deferred-envelope-type predicate in Go. Reuse that predicate from receiver ACK deferral while retaining feature-flag/runtime checks. Correct the stale config relationship and retime the existing deferred-chat uncommitted fixture to `CommittedAckReserve + bounded margin`; do not change `InteractiveSendTimeout`, its literal lock, or the fixture's 50 ms receiver override.
9. Create one command/pre-write context in `SendMessageWithTransport` and reuse it through open, context-capable self-heal relay candidates, retry, and complete write; check expiry after stream open. Keep synchronous `ClosePeer` and public duration wrappers. Adapt the tests-only `SendMessageWithTimeout` only as required by a shared helper signature and preserve its current lifecycle/error API.
10. Give `RendezvousDiscoverWithTimeout` one command context before candidate iteration and install that exact deadline on every candidate stream. Handle deadline-installation failure through the existing candidate reset/failover lifecycle; do not add `CloseWrite` or otherwise alter rendezvous protocol cleanup. Leave `ForEachWithResult`, `RelaySelector`, and explicit `DialPeerWithTimeout` structurally unchanged.
11. Implement chat stream lifecycle order: install pre-write deadline; start no write after its cutoff; after any successfully completed write (including the defensive deadline race), install `min(commandDeadline, writeCompletedAt+3s)`; `CloseWrite`; bounded ACK read; close on readable completion with one reset fallback if close fails; reset on deadline/I/O/half-close failure; retain written-but-unacked outward result after a complete frame write.
12. Register the new Dart helper test in both curated 1:1 arrays; add `TestR3Deadline_` and the retimed deferred-chat sentinel to the existing Go selector and batch contract without changing the eight-leg shape. Update only obsolete timeout prose/assertions in existing FDC/performance tests.
13. Run focused GREEN, representative mutation re-reds, exact preservation, curated `1to1`, affected feature/core family gates, analyzer/format/hygiene, and `./graphify-arch/refresh_arch_graph.sh --incremental`; then run the one R1-R3 aggregate `host-all` wave closure.

## Risks And Blind Spots

- A universal reserve would reject short immediate-ACK introduction sends -> TC-338-08/09 makes type scope causal and preserves the real two-second sibling.
- A helper can appear T0-based while sticky/live-relay/delete recovery constructs a new instance -> TC-338-02/04/05 assert exact allocations from controlled original-T0 elapsed time, not merely non-increasing values.
- Dart can approve a high-precision duration that floors to 3000 ms, or forward a floored zero that Go expands to its default -> TC-338-01/04/09 pin both serialization boundaries and call suppression.
- An ACK allowance can be raised in Dart while Go still renews open/recovery/I/O -> TC-338-10 through TC-338-14 independently pin native deadline identity and lifecycle order.
- A context-only rendezvous fix can leave stream I/O on `now+timeout` -> TC-338-12 requires the production candidate loop's open seam and exact `SetDeadline` recording, not the coarse bypass hook.
- A post-write helper can implement only one side of `min(...)`, or install the correct deadline after half-close -> TC-338-13 has independent early/late rows plus exact lifecycle order.
- A cleanup test can reset a valid `ack:false` frame, ignore normal-close failure, or conflate application proof with transport failure -> TC-338-14 separates readable results, close fallback, and read-error reset.
- Native observation hooks do not exist at HEAD -> Step 2 is a behavior-preserving GREEN seam checkpoint before runtime RED; it does not authorize a generalized clock or public API.
- `ClosePeer` cannot accept a context -> its synchronous call is an explicit accepted difference; R3 does not create a potentially leaking goroutine watchdog.
- The tests-only `SendMessageWithTimeout` sibling could pull R3 into a duplicate lifecycle rewrite -> TC-338-15 preserves it, while the scope permits only compatibility edits forced by a shared helper signature.
- `Future.timeout` still does not cancel FFI work -> accepted because native work is absolutely bounded; cross-FFI cancellation remains telemetry-gated.
- Lifecycle / derived-state durability: N/A — R3 adds no durable state, marker, cache, or reconstruction path; R1/R2 persistence sentinels remain in TC-338-15.
- Sibling-surface consistency: chat reuse/sticky/direct/relay, delete initial/recovery, and failed-delete retry are causal rows; immediate/default send callers are deliberately asymmetric under TC-338-08/09/15.
- Destructive-action side effects: delete/tombstone visibility and cleanup are unchanged and preserved by TC-338-05/06/15; stream reset affects transport state only after unsuccessful protocol completion.
- Invariant re-verification under new transitions: the reserve predicate is evaluated once from the outgoing frame before open/recovery and carried through the shared command context; TC-338-09/10 prevents recovery from re-entering with weaker timing rules.
- Native/mobile boundary: the claim is command/deadline/stream semantics inside Go plus Dart bridge ordering, all causally observable on host. No OS callback, mobile scheduler, public relay, or cross-device latency claim requires a device leg.

## Independent TDD Review

Verdict after revision: **ready**. Both independent audits first returned `plan-fixes-required`; no unresolved blocker, high, or medium plan gap remains.

| Review finding | Evidence state | Minimal revision applied | Status |
|---|---|---|---|
| Adapter tests could pass with fresh sticky/live-relay/delete clocks | confirmed | TC-338-02/04/05 now inject non-zero elapsed work and require exact original-T0 allocations | resolved |
| `Duration.inMilliseconds` flooring could admit 3000 ms or forward zero into Go defaults | confirmed | Scope and TC-338-01/04/09 pin `0/1ms`, `3000ms`, `3000ms+999us`, and `3001ms` | resolved |
| Native recovery/rendezvous REDs lacked observable seams | confirmed | Step 2 adds a behavior-preserving GREEN seam checkpoint; causal tests must then fail at runtime | resolved |
| Rendezvous open contexts could be fixed while stream I/O still renewed | confirmed | TC-338-12 records both context and exact stream deadline, including install failure | resolved |
| Expiry-after-open and both post-write `min(...)` branches were unproven | confirmed | TC-338-09 adds the post-open expiry race; TC-338-13 adds early/late rows and installs ACK deadline before `CloseWrite` | resolved |
| Normal-close failure and the existing 500 ms deferred-chat test were omitted | confirmed | TC-338-14 adds reset fallback; TC-338-15 retimes and selects the real uncommitted sentinel | resolved |
| Candidate topology and lifecycle scope were ambiguous | confirmed | TC-338-11/12 cover both relay/address axes; rendezvous cleanup, synchronous `ClosePeer`, the duration helper's other callers, and tests-only sibling are explicitly narrow | resolved |
| A new Go leg or broader coordinator/protocol work would be unnecessary | confirmed | Existing selector is extended in place; eight-leg shape and all hard exclusions remain | resolved |

Review lenses: L1 root cause clear; L2 causal contrast repaired; L3 sibling/fresh-clock surfaces covered; L4 RED/gate executability repaired; L5 persistence/device/destructive boundaries are either preserved by R1/R2 sentinels or N/A. Evergreen blind spots B-2, B-4, and B-9 are explicitly covered; the remaining lenses are N/A to this host-only, non-persistent change.

## Gate Cadence

- Per-plan closure: focused Dart/Go causal tests; exact R1/R2, local-budget, recovery/failover, bridge-forwarding, and performance sentinels; `bash scripts/test/host_test_gate_batch_contract_test.sh`; `./scripts/run_test_gates.sh 1to1`; affected `feature-host-all` and `core-host-all` because production changes span feature application code and the core bridge.
- Do not treat full `host-all` as an individual Plan 338 causal gate. After every Plan 338 done criterion is green, run `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter failures-only` once as the named R1-R3 correctness-wave closure. The final rollout/release closure remains after R5.
- Shared tests outside feature/core globs: run `test/performance/send_path_budget_hard_gate_test.dart` and the Go node/bridge suites by exact command; register the new node deadline prefix and retimed deferred-chat sentinel in the existing synthetic host-all leg.
- No required device/iOS/real-relay leg: host virtual time, bridge fakes, scripted streams, and in-process libp2p hosts prove the deadline contract. A device run would measure UX latency rather than close these causal invariants.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated staged/unstaged work.
git status --short
git diff --cached --name-status

# Native preservation baseline, then repeat unchanged after the Step 2
# observation-seam checkpoint; expect every named test selected and green.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat$|TestSendMessage_RetriesChatStreamOpenAfterSelfHeal$|TestSendMessage_RetriesNoAddressesOpenErrorAfterSelfHeal$|TestSendMessage_DoesNotSelfHealNonRetryableOpenErrors$|TestSendMessage_OpensChatStreamsWithAllowLimitedConnAndDialTimeout$|TestSendMessageWithTimeout_OpensChatStreamsWithAllowLimitedConnAndDialTimeout$|TestSendMessageWithTransport_AckFrameValidation$|TestRendezvousDiscover_TriesSecondRelayWhenFirstFails$)' \
  -count=1 -v)

# First causal RED after adding tests and the behavior-preserving seam checkpoint,
# but before contract-changing production edits. Expect non-zero:
# the four live adapters still pass 1.5-2s and the timeout-honoring fake rejects
# the ~2.2s committed ACK. Confirm the named test is selected.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R3 committed ACK window is shared by reuse sticky cold direct and live relay'

# Independent Dart REDs. Expect non-zero for fresh T0/phase budgets and absent
# discover/dial bridge watchdogs; never accept a runner timeout as evidence.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R3 T0 includes envelope preparation before live send admission'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'R3 explicit discover dial and send watchdogs are native budget plus margin'

# Native RED after the behavior-preserving seam checkpoint and after adding
# deadline_contract_test.go. Expect all TestR3Deadline_ cases discovered and
# non-zero. A brief compile RED is allowed only for a new reserve/helper symbol;
# TC-338-10/11/12 must reach runtime assertion RED, never zero-test or compile-only.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestR3Deadline_' -count=1 -v)

# Focused Dart GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/features/conversation/application/outgoing_live_deadline_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/core/bridge/p2p_bridge_client_test.dart

# Native deadline GREEN plus exact recovery/failover/ACK preservation; expect
# every named test selected and zero failures.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestR3Deadline_|TestDirectConfirmTimeout_StaysWithinCommittedAckReserve$|TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime$|TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat$|TestSendMessage_RetriesChatStreamOpenAfterSelfHeal$|TestSendMessage_RetriesNoAddressesOpenErrorAfterSelfHeal$|TestSendMessage_DoesNotSelfHealNonRetryableOpenErrors$|TestSendMessage_OpensChatStreamsWithAllowLimitedConnAndDialTimeout$|TestSendMessageWithTimeout_OpensChatStreamsWithAllowLimitedConnAndDialTimeout$|TestSendMessageWithTransport_AckFrameValidation$|TestRendezvousDiscover_TriesSecondRelayWhenFirstFails$)' \
  -count=1 -v)

# Go bridge timeout forwarding preservation; expect both tests selected.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^(TestRendezvousDiscover_HonorsTimeoutMs|TestDialPeer_HonorsTimeoutMs)$' \
  -count=1 -v)

# R1/R2 authority and settlement preservation; expect exit 0.
flutter test \
  test/core/database/helpers/outgoing_transport_settlement_test.dart \
  test/features/conversation/application/outgoing_transport_settlement_writers_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R2 first authenticated committed ACK settles before virtual transport grace'
flutter test test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'R2 delete reuse race and relay require explicit authenticated commitment'
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  --plain-name 'R2 failed delete retry requires explicit committed ACK'

# Local budget and real-time hard-gate preservation; expect exit 0. Update stale
# comments only; local remains 1500ms and direct discovery remains capped at 2s.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'passes interactive local budget to the WiFi transport'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'U5 budget: a slow local leg is cut at the local budget'
flutter test test/performance/send_path_budget_hard_gate_test.dart

# Synthetic Go registration; expect the R3 prefix and deferred-chat sentinel in
# the existing node leg, with the unchanged eight-Go-invocation shape.
bash scripts/test/host_test_gate_batch_contract_test.sh

# Curated lane and affected families; expect exit 0 / zero failed tests.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene; expect no formatting drift, new analyzer issue, shell syntax error,
# or whitespace error.
dart format --output=none --set-exit-if-changed \
  lib/core/bridge/p2p_bridge_client.dart \
  lib/features/conversation/application/outgoing_live_deadline.dart \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/features/conversation/application/retry_failed_messages_use_case.dart \
  test/core/bridge/p2p_bridge_client_test.dart \
  test/features/conversation/application/outgoing_live_deadline_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/performance/send_path_budget_hard_gate_test.dart
test -z "$(gofmt -l \
  go-mknoon/node/config.go \
  go-mknoon/node/config_test.go \
  go-mknoon/node/node.go \
  go-mknoon/node/rendezvous.go \
  go-mknoon/node/deadline_contract_test.go \
  go-mknoon/node/send_message_recovery_test.go \
  go-mknoon/node/multi_relay_test.go)"
bash -n scripts/run_host_test_gates.sh \
  scripts/run_test_gates.sh \
  scripts/test/host_test_gate_batch_contract_test.sh
flutter analyze
git diff --check

# Refresh the app-owned architecture/TDD overlay once after the coherent code
# change; expect exit 0 and record the new fingerprint in Execution Progress.
./graphify-arch/refresh_arch_graph.sh --incremental

# R1-R3 correctness-wave aggregate closure only after Plan 338 is plan-green;
# expect all discovered host tests and the eight named Go legs to pass.
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-338-01 fails because no shared serialized-millisecond allocator exists; TC-338-02/05/06 fail because 1.5-2 second native allowances reject the controlled ~2.2s ACK; TC-338-03/04 fail because preparation/reuse/phases do not consume one T0 clock; TC-338-07 fails because discover/dial have no bridge watchdog; TC-338-08 through TC-338-14 fail at their causal assertions because reserve/type scope, shared absolute deadlines, ordered half-close, and outcome cleanup do not exist. TC-338-15 is a GREEN preservation set after its fixture-only timeout retime. TC-338-16 fails after its sentinel assertions are added until registration lands.
- Green sentinel: local WebSocket stays at 1.5s; explicit dial remains one-context; introduction still succeeds with a two-second immediate-ACK budget; default contact/reaction sends remain admitted; R1/R2 settlement remains monotonic/proof-aware; ACK-read failure stays written-but-uncommitted.
- Pre-existing dirty tree / known failure: planning began with Plan 336 staged, Plan 337 and the assessment untracked, the index carrying both staged and unstaged unrelated edits, and a large unrelated notification/iOS working tree. Execution must patch only R3-owned hunks and must not stage/revert unrelated work. Native focused baseline reported green for current recovery, ACK parser, rendezvous failover, and timeout cleanup sentinels.
- Environment blocker: none for host closure. Device availability is N/A because R3 makes no OS/mobile/real-relay claim.
- Scope drift: any need for a new wire protocol/capability, generic timeout framework, cross-FFI cancellation, presence/inbox change, schema work, route/ranking change, or unrelated feature-orchestration rewrite blocks execution and returns that work to its named owner.
- Evidence-strength note: TC-338-09 preserves introduction/contact/reaction type scope through the pure `deadlinesForMessage` helper rather than an end-to-end `SendMessageWithTransport` call. The production path invokes that same helper; this is a proof-depth limitation, not an observed behavior gap.

- [x] Every owned R3 behavior has a named causal test or justified current-source preservation proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded. Focused GREEN and the exact serialized-millisecond boundary mutation (`>` to `>=`) are captured; a distinct pre-production causal RED was not preserved.
- [x] The native observation-seam checkpoint is behavior-preserving and its exact recovery/failover/ACK sentinels are green before causal contract changes.
- [x] Dart uses one six-second T0 leg, exact three-second reserve, and 500 ms bridge margin across every ordinary authenticated live-send adapter.
- [x] Dart admission uses serialized milliseconds: discover/dial never forward `0`, and deferred sends require `timeoutMs > 3000` after flooring.
- [x] Envelope preparation and failed earlier live phases consume remaining time; no adapter restarts the leg.
- [x] Initial delete and failed-delete replay obey the documented deadline/inbox-order contract.
- [x] Discover/dial/send bridge watchdogs are looser than native and fit within the Dart leg; null-timeout callers are preserved.
- [x] Rendezvous discovery contexts and stream I/O, plus message open/recovery/candidates/retry/write/ACK, each use one absolute native command deadline; explicit dial remains one-context.
- [x] Reserve-bearing sends finish open/recovery and start no write after the pre-write cutoff, reject an expired post-open stream, and clamp any successfully completed write race so ACK/half-close never exceed the command deadline.
- [x] The post-write deadline is installed before `CloseWrite`; normal `Close`/fallback `Reset` match the outcome table while written-but-unacked outward semantics remain unchanged.
- [x] Immediate-ACK introductions and unrelated default-budget callers are not rejected by the reserve.
- [x] R1/R2 settlement, local cutoff, relay scheduling, deletion cleanup, and self-heal/limited-connection behavior pass unchanged in the owned preservation selectors.
- [x] New Dart/native tests and the retimed deferred-chat sentinel enter the existing real gates; the eight-Go-tail shape is preserved.
- [ ] Focused tests, curated `1to1`, affected feature/core family gates, analyzer, formatting, shell syntax, and diff hygiene pass. Focused, `1to1`, analyzer, formatting, syntax, and hygiene are green; the family commands remain red on the documented checkpoint-reproduced Plan 337 expectations, plus one group test that passed twice alone and in `host-all`.
- [x] The incremental architecture graph refresh passes and its resulting fingerprint is recorded.
- [ ] The one post-plan R1-R3 `host-all` correctness-wave closure passes and is not repeated as an ordinary per-plan causal gate. It ran once and all eight Go legs passed, but Flutter retained the same four checkpoint-reproduced Plan 337 expectation failures.
- [x] No DB migration, device/relay requirement, performance threshold, protocol, coordinator, or cancellation framework was introduced.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'R3 committed ACK window is shared by reuse sticky cold direct and live relay'` after adding the named test and timeout-honoring fake behavior.
- Preservation command: the exact R1/R2/local/native selectors in Acceptance Gates, followed by curated `1to1` and affected family gates.
- Manual registration: add `outgoing_live_deadline_test.dart` to `ONE_TO_ONE_HOST_TESTS` and `ONE_TO_ONE_TESTS`; add `TestR3Deadline_` plus `TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat` to the existing `GO_NODE_LIBP2P_REFACTOR_RUN` selector and batch-contract sentinels. Do not add a Go invocation.
- Migration: none.
- Boundary closure: host-only for Plan 338; one full host-all after plan-green closes the R1-R3 correctness wave.
- Unresolved evidence: production timing percentiles for later six-second-leg tuning; not a correctness blocker.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-05 19:30 CEST | checkpoint | whole pre-existing tree | `git commit` -> `10c4bdb35` | Exact pre-R3 worktree preserved in `chore: checkpoint work before plan 338` | R3 can be isolated from all prior edits | Implement only R3-owned surfaces |
| 2026-08-05 execution | causal native/Dart implementation | deadline allocator; chat/delete/retry adapters; bridge watchdogs; Go config/send/recovery/rendezvous; focused tests | Integrated R3 Dart set -> 274 pass; final Go selector -> pass; Go bridge timeout tests -> pass | Six-second entry T0, floored admission, type-scoped reserve, shared absolute native deadlines, half-close/cleanup outcomes, and preservation sentinels are executable | None in R3 scope | Run preservation and real-gate registration checks |
| 2026-08-05 execution | mutation proof, GREEN, and hygiene | allocator test plus all changed Dart/Go/gate files | Mutating committed-send admission from `>` to `>=` made the exact 3000 ms boundary test fail; restore made it pass; `flutter analyze` -> no issues; format/syntax/diff checks -> pass | Representative mutation re-red is causal, but no distinct pre-production RED was retained; Dart compiles cleanly; Go compile-only and gate batch contract pass | Evidence limitation documented | Run curated and affected host lanes |
| 2026-08-05 execution | curated and affected lanes | registered `1to1`, feature, and core host selections | `1to1` -> 2818 pass; feature -> 8828 pass / 1 fail; core -> 3140 pass / 4 fail | The feature failure passed twice in isolation and later in `host-all`. All four core failures are stale LAN-authority expectations in `transport_switch_learned_invalidation_test.dart` and `f1_wifi_relay_fallback_test.dart`; the identical four failures reproduce from checkpoint `10c4bdb35` | Repository-wide family gate is not green, but no R3 regression is present | Record exception and run the one wave-level closure |
| 2026-08-05 execution | graph closure | app-owned architecture graph and manifest | `./graphify-arch/refresh_arch_graph.sh --incremental` -> pass | 11 changed code files, 3063 unchanged, 0 deleted; refreshed fingerprint `5381ccd663846180` | None | Run the one post-plan `host-all` command |
| 2026-08-05 20:49 CEST | R1-R3 wave closure | all discovered Flutter host tests plus eight named Go legs | `host-all --batch-flutter --concurrency 4 --reporter failures-only --continue-on-failure` -> Flutter `+13571 ~1 -4`; all eight Go legs pass | The only failures are the same four Plan 337 LAN-authority expectations reproduced at the checkpoint; the isolated feature flake did not recur | Host closure accurately remains red for inherited expectations; rerunning `host-all` is prohibited by cadence | Commit the implemented R3 change with this exception documented |
