# 340 - Presence-Independent Durability Hedge

Status: implemented — causal, curated, feature-host, and R4-R5 wave gates green
Type: Bug
Spec: UI-14-Conn-Type/go-libp2p-transport-assessment-review.md, R4
Classification: implementation-complete / host-green
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-05 23:05 CEST | Evidence Collector | R4 assessment; current 1:1 send orchestration; R1-R3 production contracts; implemented R5 plan; presence, send, SQL, and gate tests | Confirmed that reuse/sticky can return before inbox scheduling, connected/LAN peers have no hedge, and awaited presence still delays live work | Bound the change to the existing `sendChatMessage` orchestration seam |
| 2026-08-05 23:14 CEST | Planner | Inbox outcome API, production inbox coordinator, all current concurrent/sequential inbox funnels, fakes, timer tests, and caller/gate census | A Boolean timer would lose `expiresAtMs`/`rejectedFull`; one private typed start-or-join hedge can preserve the current protocol and failure retry | Define causal timing, authority, outcome, and callback-order contracts |
| 2026-08-05 23:23 CEST | Planner | Obsolete presence/FDC-03 assertions, R5 TC-339-05, current dirty tree, and R4-R5 wave cadence | Host fakes expose every decision point; no native, schema, public service, device, queue, or coordinator change is justified | Submit Plan 340 to `$tdd-review` and revise in place |
| 2026-08-05 23:35 CEST | Independent TDD Reviewer | Current plan, send orchestration, outcome API, canonical wrapper/fakes, ordinary/private writers, and gates | `plan-fixes-required`: cancellation exits, complete typed outcomes/retry recovery, fixture prerequisites, stage ordering, throwing presence, and private late custody needed stronger causal proof | Apply only the source-backed plan deltas |
| 2026-08-05 23:43 CEST | Planner + Independent TDD Reviewer | Revised TC-340-01/02/06/07/08/09, fixtures, mutations, exact gates, scope guard, and five-lens counterexample sweep | Final verdict `ready`; no remaining required delta or user-owned decision | Execute causal fixture preparation and REDs when authorized |

## Problem And Evidence

- Behavior to improve: live delivery work must not wait for relay-presence advice, while a stale connected/LAN observation must not postpone durable inbox custody until every live attempt has exhausted its budget.
- User impact: a backgrounded or network-switching recipient can still look connected or LAN-visible. That path currently receives no concurrent custody operation, so text or media-envelope durability can be delayed by the live ladder. Conversely, an `unreachable` presence result explicitly makes live work wait for inbox completion.
- Confirmed root causes in `lib/features/conversation/application/send_chat_message_use_case.dart`:
  - `T0` already starts at function entry through `sendStopwatch` and feeds R3's absolute live deadline (`:283-284`).
  - The exact encrypted envelope is durably staged before routing observations (`:589-731`); this is the earliest safe point for any inbox transport side effect.
  - authenticated reuse can return at `:749-814` and authenticated learned direct/relay reuse at `:845-905`, before `unknownPresence` and inbox scheduling exist;
  - `unknownPresence` at `:934-937` excludes current connections, `isConnectedToPeer`, and LAN visibility;
  - only that unknown group starts the current concurrent inbox future at `:968-1030`;
  - presence is awaited for up to 400 ms at `:1040-1047`, and `unreachable` then awaits the inbox future at `:1059-1073`, before live futures are built at `:1087+`;
  - the uncommitted and all-failed tails can independently call inbox storage at `:1382-1452` and `:2323-2388`, so adding a timer without joining those funnels would duplicate a successful deposit;
  - authenticated commitment is already classified consistently by `provesDeviceDeliveryForCurrentProtocol` and exits through reuse, sticky, or the proof race. These are the only cancellation-authority sites R4 needs.
- Confirmed detailed-outcome constraint: connected/LAN paths currently reach `effectiveStoreInInboxDetailed`, whose `InboxStoreOutcome` preserves `expiresAtMs`, treats `duplicate` as accepted, and maps `rejectedFull` to retryable `sent`. A speculative Boolean-only hedge would regress those semantics or cause a redundant second call.
- Confirmed persistence dependency: Plan 336/R1 already permits `inboxed -> delivered`, rejects `delivered -> inboxed`, and protects private-media user intent atomically. R4 must exercise that contract instead of using the process-local `liveDelivered` flag as the correctness authority.
- Existing useful coverage:
  - `outgoing_transport_settlement_test.dart::first delivered result owns fields across both callback orders` proves the real SQL transition boundary;
  - R2's claimed-LAN-ACK test proves WebSocket evidence is not delivery authority;
  - R3's shared committed-ACK-window test proves the T0 deadline contract R4 must not retime;
  - R5 TC-339-05 proves attachment relay failure reaches exactly one accepted inbox deposit;
  - the offline roundtrip proves the existing unknown-peer inbox copy drains on resume;
  - existing false-result coverage proves today's initial-plus-terminal two-call failure behavior, while `_ThrowOnInboxP2PService` lacks a call counter and does not prove throwing-call recovery. TC-340-08 adds the missing causal failed/throwing-then-accepted proof without changing retry policy.
- Obsolete opposite coverage to rewrite:
  - `send_presence_emphasis_test.dart::unreachable presence commits inbox first then live (best-effort)` requires the ordering R4 removes;
  - its late-custody test requires the `liveDelivered` flag to suppress even an atomic candidate settlement;
  - FDC-03 P1/P2 describe connected/LAN sends as permanently outside concurrent inbox work. Their immediate zero-call result remains useful only after being strengthened to advance beyond the hedge and prove authenticated cancellation.
- Refuted additions:
  - no new peer/conversation coordinator, outbound queue, discovery pipeline, ACK level, relay state, database transition, Go deadline, or cross-FFI cancellation is needed;
  - no physical-device or real-relay run can improve the causal proof of this Dart scheduling decision over deterministic virtual time.
- Unresolved evidence: the initial 2.5-second value is a starting policy within the assessment's 2.5-3 second range, not a permanent optimum. Production committed-ACK and duplicate-inbox/push percentiles own later tuning.

Principal production file:

- `lib/features/conversation/application/send_chat_message_use_case.dart`

Principal test files:

- `test/features/conversation/application/send_presence_emphasis_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`

Exact preservation files:

- `test/core/database/helpers/outgoing_transport_settlement_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `6b96acb19b528031`; `confidence=anchored`, `freshness=current`.
- Planning query / profile: `python3 graphify-arch/tdd_context.py query "R4 presence-independent durability hedge sendChatMessage RelayPresenceLookup unknownPresence concurrentInbox reuse sticky kInboxHedgeDelay TC-339-05 send_presence_emphasis_test.dart" --profile tdd --budget 700`.
- Primary anchor: `send_chat_message_use_case.dart`; surfaced relations included `sendChatMessage`, `RelayPresenceLookup`, `send_presence_emphasis_test.dart`, and the existing send-test wrapper/fake.
- Graph gaps requiring source verification: the compact result did not expose the current detailed-inbox outcome, all three terminal inbox funnels, or exact curated/family registration. Those were verified directly in the source and gate scripts.
- Reuse rule: this snapshot narrows navigation only; every line, test name, and gate below was checked against the current working tree.
- Review queries / profile: `python3 graphify-arch/tdd_context.py query "Plan 340 R4 presence-independent durability hedge T0 2500 start-or-join InboxStoreOutcome expiresAtMs rejectedFull authenticated commitment cancel WebSocket late custody TC-339-05 counterexample bypass" --profile review --budget 800`, then the single exact-anchor refinement `python3 graphify-arch/tdd_context.py query "send_chat_message_use_case.dart send_presence_emphasis_test.dart unknownPresence concurrentInbox effectiveStoreInInboxDetailed _completeSuccessfulSend _persistOutgoingSendResult R4 Plan 340" --profile review --budget 800`; both were `confidence=anchored` at the same current fingerprint. The first over-weighted unrelated `InboxStoreOutcome`/WebSocket labels; the refinement found `_persistOutgoingSendResult` but still required the direct source verification recorded above.

## Scope Contract And Guard

In scope:

- Add one initial public scheduling constant, `kConnectedPeerInboxHedgeBudget = Duration(milliseconds: 2500)`, measured from the existing `sendChatMessage` entry stopwatch. `T0` is after any upstream media upload and before validation/encryption/staging; it is not the original UI tap.
- After successful envelope staging and before reuse/sticky early returns, classify the peer once using the existing connection and LAN observations and create one private, send-scoped start-or-join inbox hedge.
- Structurally unknown peers start the hedge immediately once the staged encrypted envelope exists.
- Connected, live-connected, circuit-connected, or LAN-visible peers schedule the hedge for the remaining portion of `T0 + 2.5s`; if preparation/staging already consumed the budget, start immediately.
- If live work is uncommitted or all eligible live legs fail before the bound, force-start and join that same hedge immediately. Do not make a known failure wait for the timer.
- Make the hedge result `InboxStoreOutcome`-typed. Prefer the existing `effectiveStoreInInboxDetailed`; normalize the legacy Boolean seam to `stored`/`failed` only when no detailed capability was supplied.
- Preserve `stored`/`duplicate`, exact `expiresAtMs`, and `rejectedFull` behavior. An accepted or rejected-full initial result is authoritative for this send and must not start another store. An actual `failed`/throwing initial attempt may retain today's one terminal retry; R4 does not weaken retry-after-failure.
- Cancel only a scheduled-but-not-started hedge, synchronously when an authenticated explicit committed libp2p result is recognized at the reuse, sticky, or proof-race seam and before awaiting persistence. A started operation completes.
- Keep presence lookup in its current cold, structurally-unknown race scope, after committed reuse/sticky exits. Construct the eligible live futures first (or explicitly defer the refresh to the event queue), then launch the bounded cache/telemetry refresh without awaiting it. Contain timeout/errors, remove the `unreachable -> await inbox` ordering branch, and retire `CHAT_MSG_PRESENCE_INBOX_FIRST`. This prevents synchronous lookup work from delaying live launch and avoids new presence traffic on a committed sticky fast path.
- On accepted custody, attempt the existing atomic `inboxed/inbox` settlement even if a live result may already have committed. Emit `CHAT_MSG_SEND_CUSTODY_CONFIRMED` only when the authoritative observed row is actually at the custody milestone; the R1 mutation, not `liveDelivered`, decides whether a late weaker candidate applies.
- Keep `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` correlated by message ID and emit it when storage actually starts, not merely when a delayed timer is armed. Keep per-leg metrics one record per real store call.

Must preserve:

- Transport side effects begin only after the exact ordinary/private attempt is durably staged.
- R1 monotonic settlement and private hide/delete ownership.
- R2 proof authority: a nonce-correlated/claimed-committed local WebSocket result is written-only and cannot cancel custody, deliver, or train sticky state.
- R3's one T0 live deadline, three-second committed-ACK reserve, and native/bridge budgets. The 2.5-second inbox timer overlaps but does not extend or restart them.
- R5's UTF-8 envelope eligibility and exactly one accepted inbox deposit after a failed attachment relay-live attempt.
- The existing one retry after an actual failed/throwing speculative inbox call, wire-envelope retention, retryable terminal state, receiver message-ID deduplication, relay idempotency, readiness proof, and transport metrics.
- Presence remains advice/telemetry only and is not consulted for already-connected peers; R4 does not create new presence traffic.

Hard `Do not`:

- Do not add a public coordinator/state machine, second outbound queue, per-conversation ordering protocol, route scorer, network-generation state, or route-specific hedge values.
- Do not add pending/activate/tombstone inbox states, cancel an inbox request after it starts, or add cross-FFI/native cancellation.
- Do not change a database schema, status transition, wire envelope, ACK protocol, Go/native transport, relay backend, DCUtR, discovery, dial ranking, resource-manager policy, or media upload/download behavior.
- Do not remove the transitional WebSocket attempt in R4; only preserve its lack of delivery/cancellation authority.
- Do not broaden the change to delete, reaction, receipt, contact, introduction, group, post, profile, or cached-envelope retry policies.
- Do not add a new shared fake, gate entry, device topology, real relay, or wall-clock sleep.

Deferred / accepted difference:

- Hedge tuning remains telemetry-gated. Start with one 2.5-second constant; do not pre-design adaptive or per-route policy.
- Removal of WebSocket chat delivery and foreground connection single-flight remain conditional follow-up plans under the assessment, not Plan 340.
- A started inbox operation may finish/store/push after a live commitment. This is intentional; receiver/relay idempotency and R1 atomic settlement own the duplicate race.

Dependencies:

- Plans 336-338 / R1-R3 are implemented and are hard prerequisites.
- Plan 339 / R5 is already implemented out of preferred order. Plan 340 must re-run and strengthen TC-339-05, then closes the R4-R5 durability/relay wave.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-340-01 | Slow/unreachable or throwing presence advice cannot delay or fail eligible authenticated live work | rewrite as `send_presence_emphasis_test.dart::R4 slow unreachable or throwing presence cannot delay authenticated live launch or settlement` | Dart host; mandatory two-row table extends `_PresenceFake` with (a) a controlled unresolved future later completed as `unreachable` and (b) `Future.error(StateError(...))`; each row uses an unknown peer, explicit authenticated direct ACK, and a failed inbox result | HEAD does not construct live work until the controlled lookup resolves/400 ms and lets the throwing lookup escape -> GREEN launches/settles `delivered/direct` independently in both rows; later advice may emit best-effort emphasis but never `PRESENCE_INBOX_FIRST` | reintroduce `await lookupRelayPresence`, restore the unreachable inbox await, invoke refresh before live futures are constructed/event-deferred, or omit async error containment -> row red | exact focused command; file already in `ONE_TO_ONE_TESTS` and feature auto-glob |
| TC-340-02 | A structurally unknown peer starts one staged-envelope inbox hedge before a committed learned direct/relay early return without adding a presence lookup | new `send_presence_emphasis_test.dart::R4 structurally unknown peer starts one inbox hedge between staging and committed sticky return` | Dart host; non-connected/non-LAN `_PresenceFake`, learned `direct`, explicit authenticated ACK, accepted inbox, repository `stage` marker, and ordered `inbox-call`/`sticky-send` markers | HEAD records `stage, sticky-send` with zero inbox calls -> GREEN records exact order `stage < inbox-call < sticky-send`, exactly one store, zero discover/dial, zero presence lookups, and final `delivered/direct`; a late accepted result cannot downgrade it | move hedge before staging or below sticky, start it after sticky send, move presence above sticky, or launch a second accepted store -> order/count/status red | exact focused command; existing registration |
| TC-340-03 | Connected reuse hedges exactly at `T0 + 2.5s`, preserves detailed custody/expiry, and late commitment upgrades custody | new `send_presence_emphasis_test.dart::R4 connected reuse hedge starts at T0 bound and late proof upgrades custody` | Dart host `fakeAsync`; direct connection in `NodeState`, controlled reuse ACK held past the bound, injected detailed store returns `stored` with fixed `expiresAtMs`, and `TransportMetrics` observes the real call | HEAD has zero store at the bound -> GREEN has zero at bound-minus-1 ms and one detailed/zero Boolean call plus exactly one successful inbox-attempt metric at the bound, atomically observes `inboxed/inbox` with exact expiry, then a released authenticated ACK ends `delivered/direct` with custody fields cleared | exclude connected peers, restart the timer at reuse/envelope readiness, use Boolean store, double-record the call, drop expiry, or block `inboxed -> delivered` -> row red | exact focused command; existing registration |
| TC-340-04 | A LAN WebSocket write/claimed commitment cannot cancel the delayed hedge | new `send_presence_emphasis_test.dart::R4 LAN WebSocket evidence cannot cancel the T0 inbox hedge` | Dart host `fakeAsync`; LAN-visible `DurableLanFakeP2PService`, immediate `LanSendAck.committed`, authenticated direct result held beyond the bound, accepted inbox | HEAD has no call at the bound -> GREEN proves the local write occurred, zero store before the bound, exactly one at it, and final inbox custody when the authenticated leg fails | cancel on local success/written evidence, omit LAN scheduling, or allow a second fallback call after acceptance -> row red | exact focused command; existing registration |
| TC-340-05 | Envelope preparation consumes, rather than restarts, the connected/LAN hedge budget | new `send_chat_message_use_case_test.dart::R4 envelope preparation consumes the connected peer inbox hedge budget` | Dart host `fakeAsync`; existing `_R3DelayedCryptoBridge` consumes 2.4 seconds, staged connected peer, held authenticated send, accepted inbox, then the remaining 100 ms is advanced | HEAD proceeds into live work with zero hedge calls -> GREEN performs no store before the envelope is staged, remains at zero through `T0 + 2499.999 ms`, and starts exactly once at the original `T0 + 2.5 s` bound | create the stopwatch after encryption/staging or always wait a fresh 2.5 seconds -> row red | exact focused command; file already in both 1:1 arrays and feature auto-glob |
| TC-340-06 | Authenticated commitment cancels the timer before persistence at every current committed-ACK exit | rewrite/strengthen FDC-03 P1/P2 as `send_chat_message_use_case_test.dart::R4 authenticated libp2p commitment cancels every scheduled unstarted hedge` | Dart host `fakeAsync`; mandatory four-row table covers connected reuse, LAN-visible learned-direct sticky reuse, direct proof-race, and circuit-only relay proof-race; a tiny test-only ordinary repository gate holds delivery persistence across the hedge bound | GREEN sentinel on HEAD and after R4: each row recognizes explicit authenticated commitment before the bound, persistence remains blocked while virtual time advances beyond it, zero detailed/Boolean stores occur, final state is `delivered` on the expected direct/relay route, and no timer fires after return | cancel after persistence/return, omit any of the four exits, key cancellation only to route text rather than authenticated commitment, or leave a returned-send timer armed -> owning row red | exact focused command; existing registration |
| TC-340-07 | Once inbox storage starts, a later live commitment cannot cancel it; ordinary and protected-private late custody both reach their atomic writer without downgrading delivery | new `send_chat_message_use_case_test.dart::R4 started hedge completion after live ACK cannot downgrade ordinary or private delivery` | Dart host two-row table; unknown peer starts one controlled detailed-store future, authenticated direct ACK settles first, then inbox resolves accepted. Ordinary row captures `ordinarySettlementCalls`; protected one-more-look row extends the existing private custody fake to capture settlement arguments. Pair with both real-SQL R1 sentinels | HEAD's `liveDelivered` guard suppresses the late `inboxed` candidate -> GREEN invokes the correct ordinary/private atomic writer with that candidate, observes authoritative `delivered/direct` unchanged, emits no false custody milestone, and makes no second store | retain `!liveDelivered`, cancel an active operation, cover only ordinary, route private through generic save, bypass atomic mutation, or emit custody from candidate rather than observed state -> row red | exact focused test plus exact ordinary/private SQL sentinels; existing registration |
| TC-340-08 | The typed hedge preserves every detailed outcome, exact expiry, retry recovery, and one attempt metric per real call | new `send_presence_emphasis_test.dart::R4 typed hedge preserves outcomes retries and per-call metrics` | Dart host `fakeAsync`; LAN-visible written-only path holds authenticated work across the bound, then fails. Mandatory rows script: `stored(expiry A)`, `duplicate(expiry B)`, `rejectedFull`, `failed -> stored(expiry C)`, and `throw -> duplicate(expiry D)` through an injected counted detailed callback; inherited Boolean counter and real `TransportMetrics` remain observable | HEAD has no call at the bound and later funnels are not one typed operation -> GREEN: accepted rows make one detailed/zero Boolean call, preserve the exact expiry and one successful metric; rejected-full makes one call/one failed metric, no custody, no retry, and ends retryable `sent/inbox`; failed/throw rows make exactly two detailed/zero Boolean calls, record `[false, true]`, recover to `inboxed/inbox`, and retain the accepted retry expiry | collapse to Boolean, omit duplicate/throw recovery, retry capacity rejection, lose expiry, reuse a failed future instead of issuing the one allowed retry, leave `_persistOutgoingSendResult` on its raw store, or record metrics per join instead of per call -> row red | exact focused command; existing registration |
| TC-340-09 | Either terminal non-proof funnel before the delayed bound force-starts the same hedge, and no orphan timer creates a second accepted deposit | new `send_chat_message_use_case_test.dart::R4 early uncommitted result force-starts one hedge before its bound`; strengthen `::R5 eligible attachment relay-live failure falls to one durable inbox deposit` | Dart host `fakeAsync`; row A uses a connected/LAN written-only result that reaches `_persistOutgoingSendResult` before 2.5 seconds; row B retains the circuit-only uploaded attachment whose relay fails at 500 ms. Both use accepted inbox and advance beyond 2.5 seconds | Row A RED on HEAD because its sequential raw store is not the shared typed hedge -> GREEN force-starts the typed hedge immediately. Row B is GREEN on HEAD and remains so. Both settle `inboxed/inbox` at the known terminal time, make exactly one store, and remain at one after the old timer bound | wait only for the timer, fix only the all-failed funnel, start a separate sequential store, or leave the timer armed after force-start -> owning row latency/type/count red | two exact commands; file already registered |
| TC-340-10 | R1-R5, stage-before-network, unknown-peer drain, private user intent, and failed-store terminal behavior stay intact | existing `outgoing_transport_settlement_test.dart::first delivered result owns fields across both callback orders`; `send_chat_message_use_case_test.dart::attempt staging is authoritative before transport and late terminal work cannot replace delivery`; `::R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky`; `::R3 committed ACK window is shared by reuse sticky cold direct and live relay`; `offline_inbox_roundtrip_test.dart::FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume`; `send_chat_message_use_case_test.dart::when all P2P paths fail and inbox also fails, message persists as failed`; `::total send failure records failed attempts for every leg it tried`; `::private hide after envelope handoff wins blocked transport settlement`; `outgoing_direct_private_writer_guard_test.dart::private transport settlement is column-only and concurrent intent wins` | Dart host; real SQL/private helpers plus existing integration/application fakes | GREEN on HEAD and after R4 -> refused staging has zero transport, monotonic fields, proof strength, deadlines, receiver drain, two failed inbox calls and metrics when both the speculative call and its one terminal retry fail, and private lifecycle ownership remain unchanged | start before staging, bypass atomic settlement/proof, restart R3 timer, suppress unknown deposit, remove/double-record failed-store terminal behavior, or use generic private save -> owning sentinel red | exact commands; existing curated/family registration, no gate edits |

### Test Notes

- Before any RED run, extend only the canonical test harness: forward an optional `StoreInInboxDetailedFn` from the shared `sendChatMessage` wrapper, let `_PresenceFake` inject a controlled/throwing presence future and a scripted detailed-store callback, and expose detailed-call/order counters. Extend the existing private custody fake with captured settlement arguments. These fixture-only changes must stay behavior-neutral on HEAD; a compile failure is not RED evidence.
- TC-340-01 must assert direct discovery/send start or settlement, not merely `storeInInbox`, while the presence future is unresolved. The throwing row is mandatory. Complete controlled futures during cleanup so the test does not leak asynchronous errors.
- TC-340-02's unknown peer cannot take the connected-reuse branch by definition; learned direct/relay is the real unknown-peer early-return bypass. Require `stage < inbox-call < sticky-send` and `presenceLookupCount == 0`; terminal counts alone cannot prove placement. Scheduling before connected reuse is still required for TC-340-03/06.
- TC-340-03/04/08 must hold authenticated work unresolved across the exact boundary. Final `inboxed` alone is vacuous because the existing sequential fallback can produce it. Assert zero calls at `budget - 1ms`, the expected call at `budget`, and exact detailed-versus-Boolean counts.
- TC-340-03 must inspect the authoritative staged row before releasing the live ACK, because final `delivered` correctly clears relay custody metadata.
- TC-340-05 must prove both halves: no transport before successful attempt staging, then no fresh 2.5-second wait after staging. The fixture uses 2.4 seconds of preparation plus the remaining 100 ms because R3 must retain three seconds of committed-ACK reserve inside the 5.5-second T0 budget; a preparation delay greater than 2.5 seconds cannot coexist with that held authenticated leg. Use virtual time, not a real sleep.
- TC-340-06 blocks persistence after proof recognition in all four committed-ACK exits. Advancing only after the send returns would not detect cancellation incorrectly placed after the database await.
- TC-340-07 must assert both ordinary and protected-private weaker writer invocations and their final authoritative fields. Final `delivered` alone can pass through the obsolete process-local suppression.
- TC-340-08 deliberately enters the written-only `_persistOutgoingSendResult` funnel. An all-failed-only fixture could leave that second raw Boolean call site unchanged and still pass. `failed`/throwing initial calls each recover through exactly one fresh detailed call; `rejectedFull` is authoritative and is never retried. Metrics are one record per real call, not per waiter.
- Both TC-340-09 rows must advance beyond the hedge after the result. An immediate count alone cannot expose an orphan delayed timer; the uncommitted row is what proves `_persistOutgoingSendResult` force-starts rather than merely joining an already-started operation.
- Relay inbox idempotency still owns in-doubt retries by message ID. R4 does not introduce a new retry loop or attempt to cancel a request after invocation.

## Implementation Steps

1. Snapshot `git status --short` and `git diff --cached --name-status`. Preserve the current uncommitted R2/R3 documentation, resilience, shared-fake, index, and Graphify changes; do not stage or rewrite unrelated hunks.
2. Make the fixture-only preparation from Test Notes: add the wrapper's optional detailed-store forwarding, counted/scripted presence and detailed-store hooks, ordering markers, and private settlement capture. Prove the existing suite stays green before adding R4 expectations.
3. Rewrite the two obsolete presence assertions and FDC-03 P1/P2 descriptions, add TC-340-01 through TC-340-08 plus TC-340-09's early-uncommitted row before production edits, and strengthen TC-339-05 as TC-340-09's all-failed row. Run every causal test independently. Valid RED is the documented live-launch/store-count/outcome/candidate mismatch; compile failures, unselected tests, pending timers, or runner timeouts are invalid.
4. In `send_chat_message_use_case.dart`, add the single 2.5-second constant and one private send-scoped typed hedge primitive. It may own one cancelable `Timer`, one synchronously claimed start, and one stable `Future<InboxStoreOutcome>`; do not expose it as a service/coordinator or create a new production file unless Dart's local structure becomes less clear than a file-private helper.
5. Immediately after successful attempt staging, compute the existing structural observations, construct the hedge, and either start unknown peers or schedule connected/LAN-visible peers using `max(Duration.zero, budget - sendStopwatch.elapsed)`. Starting, timer firing, and cancellation must claim state before any `await`.
6. At authenticated committed connected-reuse, learned-sticky, direct-race, and relay-race proof recognition, cancel only an unstarted timer before calling `_completeSuccessfulSend`. Do nothing for local WebSocket/written-only evidence or an operation already in flight.
7. Route the uncommitted and all-failed funnels through `startOrJoin`. Carry accepted/duplicate expiry into the existing custody settlement, route rejected-full to the existing retryable path without another call, and preserve exactly one terminal retry only after a failed/throwing first call. That retry invokes the detailed capability again; it does not reuse the failed future. A fallback before 2.5 seconds force-starts and disarms the same timer.
8. Preserve the committed-sticky no-presence boundary. After a sticky miss, construct eligible live futures before invoking (or event-defer) the bounded presence refresh; contain timeout/errors, remove `PRESENCE_INBOX_FIRST`, and make late custody invoke the existing ordinary/private atomic settlement. Base the custody event on the authoritative observed result rather than a process Boolean.
9. Run focused GREEN and representative mutation re-reds: restore awaited presence, move scheduling below sticky, restart the hedge clock after preparation, exclude connected/LAN peers, cancel on WebSocket evidence, omit each of the four proof cancellations, use Boolean outcomes, cancel a started operation, retain the `liveDelivered` suppression, reuse a failed future, retry rejected-full, and leave the timer armed after force-start. Restore the intended code after each mutation.
10. Run TC-340-10 preservation, focused files, curated `1to1`, affected `feature-host-all`, analyzer/format/diff hygiene, and one incremental Graphify refresh. With R5 already complete, then run one full `host-all` as the R4-R5 wave receipt, not as a substitute for the focused causal gates.

Stop-if:

- scheduling would need transport before attempt staging;
- preserving detailed outcomes would require a new public P2P API rather than the existing injected capability;
- a change appears necessary in Go/native, schema, ACK format, relay storage, another message family, or cross-FFI cancellation;
- deterministic virtual time cannot observe the claimed timer/authority seam. Re-plan that specific boundary instead of adding sleeps or device machinery.

## Risks And Blind Spots

- Timer/ACK boundary race can start storage twice -> the private helper synchronously claims `started`/`canceled`; TC-340-03/06/09 cover the bound, every committed-ACK exit, cancellation during persistence, and orphan-timer behavior.
- A Boolean hedge can lose expiry, duplicate acceptance, or capacity rejection -> typed `InboxStoreOutcome` plus TC-340-03/08 preserves the complete current outcome set and causal failed/throwing recovery.
- Moving presence above sticky would add network/cache work to a fast path that currently returns first -> TC-340-02 requires zero lookups while still moving only inbox scheduling earlier.
- Moving the hedge earlier can violate stage-before-network -> TC-340-05 asserts no store before envelope staging and reuses R1 staging sentinels.
- Presence can remain a hidden gate through an `await`, an `unreachable` branch, or an escaping async error -> TC-340-01 controls all three without requiring new telemetry infrastructure.
- WebSocket can accidentally gain cancellation authority even though it no longer delivers -> TC-340-04 and the exact R2 sentinel separate route evidence from proof.
- A late inbox result can be silently dropped, bypass the protected-private writer, or downgrade stronger state -> TC-340-03/07 plus both real SQL boundaries prove both callback orders and authoritative event handling.
- Force-start plus the old tail can double-deposit or double-count one call -> TC-340-03/08/09 pin detailed/Boolean calls and attempt metrics, advance past the dormant timer, and permit one fresh call only after a real failure/throw.
- Detached futures can leak errors after send return -> presence and inbox continuations must contain errors; controlled futures are completed in tests.
- Lifecycle / derived-state durability: no schema or reconstruction rule changes. R1's real SQL and private-hide sentinels are rerun because R4 introduces new callback interleavings.
- Sibling-surface consistency: every full ordinary 1:1 text/media/voice/share/edit send converges on `sendChatMessage`. Cached-envelope retry, delete, reaction, receipt, contact, introduction, group, post, and profile policies are intentionally unchanged.
- Native/mobile boundary: N/A — this plan changes Dart scheduling around already-established abstract results. Host virtual time sees the exact start, result, authority, and persistence calls; no Android/iOS-specific claim is made.
- Destructive-action side effects: N/A — no deletion, migration, relay purge, or user-data rewrite occurs.

## Gate Cadence

- Per-plan closure: eight changed-behavior causal cases (including table rows), three mutation-bearing GREEN/preservation contracts, the two focused files, exact R1-R5/private/offline/failure sentinels, `./scripts/run_test_gates.sh 1to1`, and affected `feature-host-all` because the shared 1:1 send production file changes.
- Do not run `core-host-all`: no core production, schema, bridge, native, or Go file changes. Run the exact real-SQL test directly as the unchanged R1 boundary.
- `send_presence_emphasis_test.dart` is explicitly in `ONE_TO_ONE_TESTS` but not the narrower `ONE_TO_ONE_HOST_TESTS`; the curated command must be `./scripts/run_test_gates.sh 1to1`.
- Full `host-all` is not an individual causal gate. Because R5 is already closed, run it once after Plan 340's own gates as the completed R4-R5 durability/relay wave receipt. A later release closure remains separately owned.
- Shared tests outside feature/core globs: the SQL helper is run by exact command and remains registered for aggregate/wave gates.
- No required Android, iOS, simulator, or real-relay leg. Available-device policy is N/A for this host-only decision boundary.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated staged/unstaged work.
git status --short
git diff --cached --name-status

# Causal REDs before production edits; each command must select one test and
# fail for its documented scheduling/authority/outcome discriminator.
flutter test test/features/conversation/application/send_presence_emphasis_test.dart \
  --plain-name 'R4 slow unreachable or throwing presence cannot delay authenticated live launch or settlement'
flutter test test/features/conversation/application/send_presence_emphasis_test.dart \
  --plain-name 'R4 structurally unknown peer starts one inbox hedge between staging and committed sticky return'
flutter test test/features/conversation/application/send_presence_emphasis_test.dart \
  --plain-name 'R4 connected reuse hedge starts at T0 bound and late proof upgrades custody'
flutter test test/features/conversation/application/send_presence_emphasis_test.dart \
  --plain-name 'R4 LAN WebSocket evidence cannot cancel the T0 inbox hedge'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R4 envelope preparation consumes the connected peer inbox hedge budget'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R4 started hedge completion after live ACK cannot downgrade ordinary or private delivery'
flutter test test/features/conversation/application/send_presence_emphasis_test.dart \
  --plain-name 'R4 typed hedge preserves outcomes retries and per-call metrics'

# Mutation-bearing GREEN/preservation cases. Expect one selected passing test
# on HEAD and after R4; the documented R4 mutations must make them fail.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R4 authenticated libp2p commitment cancels every scheduled unstarted hedge'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R4 early uncommitted result force-starts one hedge before its bound'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R5 eligible attachment relay-live failure falls to one durable inbox deposit'

# Focused GREEN; expect exit 0 and zero failures.
flutter test \
  test/features/conversation/application/send_presence_emphasis_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart

# Exact R1-R5, offline drain, failed-store retry, and private preservation.
flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart \
  --plain-name 'first delivered result owns fields across both callback orders'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'attempt staging is authoritative before transport and late terminal work cannot replace delivery'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R3 committed ACK window is shared by reuse sticky cold direct and live relay'
flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  --plain-name 'FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'when all P2P paths fail and inbox also fails, message persists as failed'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'total send failure records failed attempts for every leg it tried'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'private hide after envelope handoff wins blocked transport settlement'
flutter test test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart \
  --plain-name 'private transport settlement is column-only and concurrent intent wins'

# Curated lane and affected feature-family closure.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene and topology refresh.
dart format --output=none --set-exit-if-changed \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  test/features/conversation/application/send_presence_emphasis_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart
flutter analyze
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Wave-level command after Plan 340 is plan-green, because implemented R5 already completes the other half of this wave:

```bash
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-340-01 waits/throws at presence; TC-340-02 returns sticky with zero stores; TC-340-03/04/08 have no hedge at 2.5 seconds; TC-340-05 would restart timing after preparation; TC-340-07 suppresses both ordinary/private late atomic candidates; and TC-340-09's early-uncommitted row uses an independent raw store. TC-340-06, TC-340-09's R5 row, and TC-340-10 are explicitly GREEN preservation/mutation contracts, not false causal RED claims.
- Green sentinel: authenticated proof still settles immediately at all four exits; no store starts before staging; a fast proof leaves no latent timer; R5 force-start stays exactly one accepted deposit; detailed outcomes, one failure retry, deadlines, proof strength, monotonic ordinary/private SQL, offline drain, and private user intent remain unchanged.
- Pre-existing dirty tree: planning observed uncommitted Plan 337/338 status records, resilience tests, shared fake, index, and Graphify output. Execution must inventory and preserve them; they are not Plan 340 scope.
- Environment blocker: none for host closure. Device and relay availability are irrelevant to this causal claim and unavailable platforms are N/A under project policy.
- Scope drift: any new schema/native/protocol/public coordinator, per-route tuning, device obligation, WebSocket removal, or change to another message family blocks Plan 340 and requires a separate decision.

- [x] Every designated changed-behavior RED fails for its documented reason before production edits; the explicit GREEN preservation/mutation rows remain selected and passing.
- [x] Structurally unknown peers start one staged-envelope hedge before sticky return, while connected/LAN peers use one 2.5-second T0 schedule.
- [x] Slow/unreachable/failed presence advice never delays or fails live launch/settlement, and `PRESENCE_INBOX_FIRST` is retired.
- [x] Connected and LAN hedge boundaries are deterministic at `budget - 1ms` / `budget`, including preparation that consumes the original T0 budget.
- [x] Only authenticated explicit libp2p commitment cancels an unstarted timer at connected reuse, learned sticky, direct-race, and relay-race exits; cancellation occurs before persistence can cross the bound.
- [x] A started operation completes; ordinary and protected-private callback orders use their R1 atomic writers and retain the stronger authoritative fields/events.
- [x] Stored/duplicate exact expiry, rejected-full, and failed/throwing recovery semantics survive the hedge without Boolean collapse or duplicate storage.
- [x] Both early-uncommitted and all-failed terminal funnels force-start/join the hedge immediately; no orphan timer creates a second accepted deposit.
- [x] The current one fresh retry after an actual failed/throwing first store remains, rejected-full is not retried, and metrics are recorded exactly once per real call with wire-envelope retention.
- [x] R1-R5, offline drain, proof authority, deadline, private user-intent, readiness, and receiver/relay idempotency boundaries pass unchanged.
- [x] Representative restarted-clock, missing-cancel, late-custody suppression, and rejected-full retry mutations re-red, then the intended implementation is restored byte-for-byte.
- [x] Focused tests, curated `1to1`, affected `feature-host-all`, analyzer, formatting, diff hygiene, and incremental Graphify refresh pass.
- [x] The completed R4-R5 wave `host-all` receipt is recorded separately from Plan 340's causal/family gates.
- [x] No gate registration, migration, Go/native, device/iOS, queue/coordinator, ACK, relay-state, discovery, ranking, or other-message-family change is introduced.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/application/send_presence_emphasis_test.dart --plain-name 'R4 slow unreachable or throwing presence cannot delay authenticated live launch or settlement'`.
- Smallest production delta: one file-private typed hedge around the existing detailed/Boolean inbox seams; schedule it after successful staging and before reuse/sticky; cancel it only at the four current authenticated commitment exits; join it from both existing non-proof tails; detach presence ordering.
- Preservation command: `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart --plain-name 'first delivered result owns fields across both callback orders'` plus the exact R2/R3/R5 commands above.
- Manual registration: none. Both causal files are already in curated `1to1`; both auto-glob into `feature-host-all`.
- Migration: none.
- Boundary closure: host-only deterministic scheduling/authority/persistence proof. No simulator, physical device, iOS, or real relay is required.
- Execution order: implement after Plans 336-339 as the final roadmap correction. Plan 339 landed first, so strengthen and re-run TC-339-05 during this execution.
- Unresolved evidence: only post-rollout tuning of the single 2.5-second value; it is not an implementation blocker.

## Reviewer Findings

Verdict: **ready**. Classification: `implementation-ready`; core bet: **confirmed**; disposition: **execute**.

- The first independent pass returned `plan-fixes-required`. Source verification showed that a narrower plan could pass while omitting learned-sticky or relay-race cancellation, `duplicate` and failed/throwing detailed outcomes, a real recovery retry, the protected-private late-custody writer, the throwing-presence path, or the exact `stage < inbox < sticky` seam.
- Those gaps are now closed in TC-340-01/02/06/07/08. Fixture preparation is explicit and behavior-neutral; the outcome table pins detailed/Boolean calls, expiry, rejection, retry, and per-call metrics. TC-340-09 additionally proves both terminal non-proof funnels force-start the same hedge before its timer.
- Wrong-implementation lens: clear after the placement, exact-boundary, all-exit cancellation, started-operation, typed-outcome, and orphan-timer mutations.
- Cause/bypass lens: clear. The root cause and all current early/terminal exits were verified in the current source; ordinary and protected-private persistence paths are both represented.
- Boundary lens: clear. Deterministic Dart host tests observe the scheduling seam, and exact real-SQL ordinary/private sentinels preserve the persistence boundary. Native, relay, and device proof are N/A because their contracts do not change.
- Concurrency/reversibility lens: clear. The plan covers pre-start cancel versus post-start completion, both callback orders, one failure retry, idempotent storage, and monotonic settlement. There is no schema, migration, destructive action, protocol, or rollback decision.
- Blind-spot sweep: asynchronous error containment, lifecycle/private state, duplicate/rejected/failed outcomes, metrics cardinality, and wave-gate cadence are covered. No unresolved user decision remains; only later telemetry may tune the single 2.5-second policy.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-06 execution | fixture baseline and causal RED | two planned Dart test files | behavior-neutral fixtures -> presence `+9`, chat `+155`; TC-340-01/02/03/04/05/07/08 and TC-340-09's early-uncommitted row each exited non-zero for the named scheduling, count, or custody mismatch; TC-340-06, strengthened R5, and preservation rows stayed GREEN | Every RED compiled and selected its owning assertion. TC-340-05 uses 2.4 seconds of preparation plus the remaining 100 ms so R3 retains its three-second ACK reserve; it proves zero at `T0 + 2499.999 ms` and one call at `T0 + 2500 ms` | None | Implement the send-scoped typed hedge |
| 2026-08-06 execution | implementation and focused GREEN | send use case plus two planned test files | focused files -> `+170`; presence -> `+13`; chat -> `+157` | One T0-based typed single-flight hedge now starts or schedules after staging, cancels only at four authenticated proof seams, force-starts at both non-proof funnels, preserves typed outcomes/retry metrics, settles late ordinary/private custody atomically, and detaches contained presence advice | None | Run mutations and preservation sentinels |
| 2026-08-06 execution | mutation and preservation | affected tests plus exact R1-R5/offline/private sentinels | restarted-clock, omitted connected-reuse cancellation, restored `liveDelivered` suppression, and rejected-full retry mutations each re-red; restored focused row and all nine exact preservation commands passed | Mutations failed on their intended `1 -> 0`, `0 -> 1`, candidate-count, and one-call-versus-two discriminators; the restored production SHA-256 matched `f0a4e826a0ee98c5bbe28494128fd523f99ece4530aea465f3712ac33fa615d7` | None | Run registered gates |
| 2026-08-06 execution | curated and affected host closure | registered 1:1 and feature host families; one directly affected thumbnail fixture | first `1to1` exposed two `UnimplementedError: isConnectedToPeer` failures in `_ReuseP2PService`; adding its truthful connected-target override made the exact file `+2`, repeated `1to1` -> Flutter `+2827` plus relay Go contracts, and `feature-host-all` -> `+8838 ~1` across 837 paths | The only reachable raw fake missing the new structural read was repaired; a separate fake census found no other send-path omission. The full required registered scopes are green and the one feature skip is expected | None | Run hygiene and the R4-R5 wave receipt |
| 2026-08-06 execution | R4-R5 wave receipt | full registered host matrix | `host-all` -> Flutter `+13584 ~1` across 1326 paths, followed by every registered host/Go contract | The once-per-wave aggregate is green; the one skip is expected and no device leg applies to this Dart scheduling boundary | None | Refresh topology and complete review |
| 2026-08-06 execution | hygiene, graph, and independent implementation review | four changed Dart files, plan, architecture graph | planned formatter gate -> 3 files / 0 changes; analyzer and diff check -> pass; incremental refresh -> 4 changed code / 3070 unchanged / 0 deleted; independent review -> approve | Graphify is current at fingerprint `c99cfc25938cfbdb`; affected-context includes the expected 1:1 callers and harnesses. No migration, Go/native, gate-registration, device, protocol, or other-message-family change was introduced; pre-existing Plan 337/338, index, resilience, shared-fake, and Graphify work remains outside this commit | None | Commit the isolated Plan 340 implementation |
