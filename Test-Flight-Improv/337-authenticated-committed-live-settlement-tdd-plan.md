# 337 - Authenticated Committed Live Settlement

Status: implemented — production proof boundary and obsolete resilience harness closed (2026-08-05)
Type: Bug
Spec: UI-14-Conn-Type/go-libp2p-transport-assessment-review.md, R2
Classification: implementation-complete / affected core-host green
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-05 16:10 CEST | Evidence Collector | R2 roadmap; chat send selector; LAN WebSocket ACK path; Go send/receive bridge; delete/retry/receipt paths; tests and gates | Confirmed that transport rank, explicit ACK proof, and WebSocket authority are conflated at several ordinary 1:1 delivery-minting seams | Define the smallest proof-aware contract and enumerate bypasses |
| 2026-08-05 16:35 CEST | Planner | Current Plan 336 implementation; local ingress transport labels; relay inbox peer binding; native ACK tests; live device inventory | R1 is closed; R2 needs no schema, signed WebSocket protocol, new coordinator, or mandatory device leg | Write causal rows, preservation sentinels, and exact gate registration |
| 2026-08-05 16:45 CEST | Planner | Existing NET-REL/FDC authority tests, `EnableDeferredDirectAck`, Go host-tail registration | Current-version/default-on libp2p ACKs are post-commit; force-off and older-peer semantics are an explicit compatibility limit | Submit the draft to an independent counterexample review |
| 2026-08-05 16:55 CEST | Independent Reviewers | Draft Test Contract; selector timers; delete adapters; receiver staging/confirm order; ingress identity; Go/relay gates | Direction confirmed; plan fixes required for deterministic timer proof, ordinary written direct/relay cases, delete adapter totality, real staging order, exact provenance tests, parser counterexamples, and registration | Apply only verified bounded deltas |
| 2026-08-05 17:03 CEST | Arbiter | Revised 15-row Test Contract, exact commands, scope guard, compatibility limit, gate cadence | All required deltas integrated without a new protocol, coordinator, DB/API surface, or device obligation; current-version/default-on release assumption remains explicit | Execute Plan 337 by TDD |
| 2026-08-05 17:09 CEST | Independent Re-review | Executable Go selectors; `GO_NODE_LIBP2P_REFACTOR_RUN`; batch-contract registration; Markdown command rendering | Corrected one alternation selector that could select no tests when copied and named every native registration target while preserving the existing aggregate eight-Go-invocation shape | Final hygiene and index registration |
| 2026-08-05 17:10 CEST | Counterexample Re-review | `fakeAsync` direct/relay timing against `kRelayLegStagger` and `transportGraceWindow` | Corrected the relay-first proof to advance only the existing 500 ms scheduling stagger, then require settlement without the additional 150 ms winner grace | Final sufficiency audit |

## Problem And Evidence

- Behavior to improve: an ordinary 1:1 text/media envelope or delete tombstone must become `delivered` only after the intended libp2p peer returns an explicit affirmative ACK that, under the current default-on receiver contract, is emitted after the encrypted envelope is durably staged into receiver-owned recovery custody. The first such proof must settle immediately. This is not a claim that the final conversation row has already been projected.
- Impact: the current selector can let a higher-ranked but unauthenticated LAN WebSocket claim mint or replace `delivered`, suppress authenticated relay/direct work and inbox custody, and train `local` as a successful route. A hostile LAN endpoint can also forge a plaintext delivery receipt and independently mint `delivered`.
- Confirmed root causes/current gaps:
  - `_RaceResult` at `lib/features/conversation/application/send_chat_message_use_case.dart:1705-1744` carries only `success` and `acknowledged`; it has no authentication/proof dimension.
  - `_tryLocalSend` at `send_chat_message_use_case.dart:1896-1940` maps `LanSendAck.committed` to `acknowledged:true`; `_persistOutgoingSendResult` at `:2441-2460` therefore mints `delivered` from an unauthenticated WebSocket claim.
  - the nonce-correlated LAN ACK at `lib/core/local_discovery/local_ws_server.dart:386-420,493-568` has no signature, session MAC, or binding to the target libp2p Peer ID; inbound `from`/`to` are caller-supplied at `:257-285`.
  - `offerSuccess` at `send_chat_message_use_case.dart:1275-1304` compares `local > direct > relay` before proof strength; the 150 ms grace and 120 ms learned-route head start can delay or replace an earlier libp2p commitment.
  - connection reuse returns on `sendResult.sent` at `:790-844`, sticky reuse returns on any `shortCircuit.success` at `:873-930`, and relay-live suppresses itself on any `best != null` at `:1204-1229`. Each can terminate or suppress stronger work on written-only evidence.
  - `SendMessageWithTransport` at `go-mknoon/node/node.go:1588-1643` sets `Acked:true` after any readable frame instead of validating a JSON object containing boolean `ack:true`.
  - `_tryLocalDeleteSend` at `lib/features/conversation/application/delete_message_use_case.dart:978-993` hard-codes a successful WebSocket write as acknowledged, while reuse/race/relay paths use proof-blind success short-circuits. `_persistOutgoingDeleteResult` at `:898-913` then hides a falsely delivered tombstone.
  - the custom failed-delete retry at `lib/features/conversation/application/retry_failed_messages_use_case.dart:940-969` can mint `delivered` through the backward-compatible reply inference rather than requiring an explicit native ACK.
  - `handleDeliveryReceipt` at `lib/features/conversation/application/handle_delivery_receipt_use_case.dart:20-72` accepts peer-string correlation but no trusted ingress provenance. Local WebSocket ingress is tagged `wifi`, while current libp2p and relay-inbox ingress is tagged `direct`, `relay`, or `inbox`; without a fail-closed allowlist, a forged LAN receipt can settle ordinary, private/view-once, or deletion rows.
- Existing coverage:
  - serial baselines on 2026-08-05 passed `send_message_result_test.dart` 7/7, `handle_delivery_receipt_use_case_test.dart` 11/11, `delete_message_use_case_test.dart` 18/18, and `GOTOOLCHAIN=go1.25.0 go test ./node`.
  - `go-mknoon/node/transport_label_test.go` has separate positive-confirm, false-confirm, timeout, nonce, and type-predicate tests. Together they prove that Go waits for Dart under the default-on contract; the nonce/type tests alone are not ACK-ordering proof.
  - `test/core/services/p2p_service_impl_test.dart` proves eventual direct staging/confirm/replay, but does not currently gate `stageEntries` and assert that `message:confirm` is absent before staging returns.
  - `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` proves LAN stage-before-ACK behavior, but not peer authentication.
  - Plan 336's atomic ordinary settlement and first-delivery freeze are implemented and device-verified; R2 must use that authority rather than introduce another persistence path.
- Missing coverage: no test distinguishes authenticated commitment from unauthenticated/written evidence throughout reuse, learned-route, the ordinary direct/relay race, deletion, retry, and receipt ingress; no deterministic virtual-time test proves zero settlement grace; no Dart test proves stage-before-confirm ordering; no Go test rejects a readable but non-affirmative ACK frame; and no gate sentinel keeps these native proofs in the wave-level host suite.
- Refuted findings:
  - explicit `acked:false` is not overridden by a non-empty reply: `SendMessageResult.acknowledged` gives the explicit Boolean precedence, and the current Go bridge always exports that Boolean. Do not remove the compatibility getter globally.
  - direct and relay libp2p streams are already authenticated to the decoded target Peer ID; no ACK signature, message hash, or public authentication field is needed for this plan.
  - mDNS already forwards private libp2p addresses into the existing coordinator; a new coordinator, Dart address racer, or signed WebSocket replacement is not required.
- Unresolved finding / accepted compatibility limit: a current receiver built with `MKNOON_ENABLE_DEFERRED_DIRECT_ACK=false`, or an older peer that emits the same `{"ack":true}` before durable recovery staging, is indistinguishable on this wire protocol. R2's `committed` claim is therefore explicitly limited to current-version peers running the production default-on contract. Stop execution if a shipping build configuration forces the flag off. Remote capability/version negotiation remains deferred unless mixed-version proof becomes a product requirement.
- Principal affected production files:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/delete_message_use_case.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/features/conversation/application/handle_delivery_receipt_use_case.dart`
  - `go-mknoon/node/node.go`
- Principal test/gate files:
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/integration/ranked_race_relay_penalty_test.dart`
  - `test/features/conversation/application/delete_message_use_case_test.dart`
  - `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart`
  - `test/features/conversation/application/delivered_status_minting_sites_test.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/services/p2p_service_inbound_transport_test.dart`
  - `test/core/inbox/inbox_staging_repository_impl_test.dart`
  - `test/core/bridge/p2p_bridge_client_test.dart`
  - `go-mknoon/node/send_message_recovery_test.go`
  - `go-mknoon/node/transport_label_test.go`
  - `go-relay-server/inbox_test.go` (existing authenticated-sender sentinel only)
  - `scripts/run_host_test_gates.sh`
  - `scripts/test/host_test_gate_batch_contract_test.sh`

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `31ab0813ec8f56ad`; current, `confidence=anchored`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "R2 authenticated committed live settlement in sendChatMessage _RaceResult offerSuccess transportGraceWindow sendLocalMessageDurable LanSendAck handleDeliveryReceipt sendDeliveryReceipt deleteMessage SendMessageWithTransport ACK frame validation; identify causal tests, bypass callers, and 1to1 gate registration" --profile tdd --budget 700`.
- Anchors:
  - `transportGraceWindow` -> `lib/features/conversation/application/send_chat_message_use_case.dart:67`
  - `_RaceResult` / `offerSuccess` -> `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `LanSendAck` -> `lib/core/local_discovery/lan_send_ack.dart:5`
  - `handleDeliveryReceipt` -> `lib/features/conversation/application/handle_delivery_receipt_use_case.dart:26`
  - `SendMessageWithTransport` -> `go-mknoon/node/node.go`
- Surfaced proof/gate files: `send_chat_message_use_case_test.dart`, `handle_delivery_receipt_use_case_test.dart`, `local_ws_durable_ack_integration_test.dart`, `send_message_recovery_test.go`, `transport_label_test.go`, `run_test_gates.sh`, and `run_host_test_gates.sh`.
- Graph gaps requiring source search: local WebSocket receipt spoof path, deletion/retry sibling minting sites, relay-inbox authenticated `from` binding, and synthetic Go host-tail registration were verified directly in current source.
- Reuse rule: these anchors may be handed to execution; every conclusion remains grounded in current source and the named causal test.

## Scope Contract And Guard

In scope:

- Introduce a private, local proof distinction at the ordinary 1:1 chat/delete orchestration seams:

  ```text
  written        = the complete frame left the sender
  explicitAck    = acked == true
  authenticated  = the attempt used the target Peer ID's libp2p stream

  provesDeviceDeliveryForCurrentProtocol = authenticated && explicitAck
  ```

  Under the accepted current-version/default-on receiver contract, that
  explicit ACK is released only after durable recovery staging. Keep this
  qualification in names/comments; do not expose an unqualified public
  `committed` API.

- Settle immediately on the first `provesDeviceDelivery` result. Transport labels remain metadata; a libp2p result may still be labelled `local`, `direct`, or `relay` without changing its authority.
- Treat every local WebSocket result, including `LanSendAck.committed`, as unauthenticated written evidence. It may remain in attempt/ACK telemetry, but cannot mint `delivered`, suppress libp2p or inbox work, or train sticky success.
- Make existing authenticated connection reuse eligible even when mDNS says the peer is local; learned `local` may no longer short-circuit authenticated work. Keep the local WebSocket leg available in the normal race as transitional written evidence.
- Validate the native reply semantically: a JSON object with boolean `ack:true` is committed; `ack:false`, missing/wrong-type `ack`, malformed JSON, JSON primitives, or an empty frame are uncommitted. Extra object fields remain forward-compatible.
- Pin both halves of that meaning: Go must not write the ACK before a positive Dart confirm, and Dart must not send `message:confirm` before durable staging returns. Keep the existing real staging-repository insert sentinel green.
- Apply the same explicit-proof rule to ordinary delete-for-everyone and its custom failed-delete retry.
- Reject incoming delivery receipts unless production ingress assigned `transport` in `{direct, relay, inbox}` before any message row is read or mutated. Preserve peer-ID correlation as the second check.
- Pin the trust basis for that allowlist: Go must derive `from` and direct/relay transport from the authenticated stream rather than envelope fields; local WebSocket ingress must stamp `wifi`; relay inbox storage must overwrite caller-supplied `from` with `RemotePeer`; and `InboxStagingEntry.toChatMessage` must stamp `inbox`.
- Update old NET-REL/FDC tests that intentionally assert LAN authority or delivery-rank grace; they are accepted behavior changes, not preservation failures.
- Register the native tests by extending the existing `GO_NODE_LIBP2P_REFACTOR_RUN` `host-all` selector and its batch-contract sentinels, preserving the aggregate eight-Go-invocation gate shape.

Old assertions intentionally replaced, not preserved:

- `send_chat_message_use_case_test.dart` cases currently asserting committed LAN -> `delivered/local` + sticky-local, LAN-visible bypass of authenticated reuse, local-within-grace replacement, learned-local full short-circuit, LAN suppression of relay-live, and later preferred-route replacement of an earlier libp2p commitment.
- `ranked_race_relay_penalty_test.dart::FDC-02 e2e: sender LAN-wins, relay-live leg never fires, receiver persists one row`; rewrite its discriminator so an unauthenticated LAN write cannot suppress the relay proof, while receiver message-ID dedup still yields one row.

Release assumption accepted by this plan:

- R2 closes current-version/default-on bridge-managed production behavior. It does not claim that the identical `{"ack":true}` bytes prove commitment from an older peer or a recipient built with deferred ACK forced off. The roadmap explicitly defers a new ACK level/capability protocol; if mixed-version proof becomes a release requirement, this plan stops and that protocol decision must be planned separately.

Must preserve:

- Plan 336 atomic settlement, exact predecessor checks, first-delivery freeze, late custody no-op, and envelope clearing -> `outgoing_transport_settlement_test.dart` and `outgoing_transport_settlement_writers_test.dart`.
- Explicit positive libp2p reuse remains a one-path fast success; relay staggering remains attempt scheduling -> named TC-337-06/15 sentinels.
- A written-but-uncommitted live result still converges to existing inbox custody or retryable `sent`, with one retained envelope -> TC-337-04/05/06.
- Local WebSocket receiver staging, duplicate handling, nonce correlation, and ACK classification remain operational transport behavior -> `local_ws_server_test.dart` and `local_ws_durable_ack_integration_test.dart`.
- Current ingress still labels local WebSocket as `wifi`, libp2p as `direct`/`relay`, and staged relay custody as `inbox` -> TC-337-10/11.
- Receiver stage-before-confirm and default-on deferred ACK remain unchanged -> TC-337-02.
- Contact requests, introductions, reactions, groups, posts, profile transfer, and local media transport retain their existing authority/status semantics; only ordinary 1:1 chat/delete delivery settlement and receipt ingress are changed.

Hard `Do not`:

- Do not add a public route-scoring/proof framework, peer coordinator, queue, cancellation protocol, native spool, new ACK level, message hash/signature, signed/MACed WebSocket protocol, or DB migration.
- Do not remove mDNS, the WebSocket server, LAN staging, or local media paths.
- Do not change deadlines, presence ordering, inbox hedge timing, attachment live-relay eligibility, DCUtR, resource-manager policy, or go-libp2p address racing; R3-R5 own those changes.
- Do not infer authentication from the persisted `transport` label. A real libp2p send can intentionally preserve `local` for display/telemetry.
- Do not globally remove `SendMessageResult.acknowledged` reply compatibility or refactor unrelated `sendMessage`/`sendMessageWithReply` callers.
- Do not require an iOS or mobile-device proof for the deterministic authority decision.

Deferred / accepted difference:

- Mixed-version or force-disabled deferred ACK capability -> explicitly accepted for this plan under the release assumption above; future protocol-capability plan only if the product requires cross-version committed proof. A local build-default test cannot establish the remote fleet's mode.
- Removal of WebSocket chat-envelope delivery -> conditional follow-up after R2-R4 and same-LAN preservation evidence.
- Receipt-send durability (`delivery_receipt` itself currently receives an immediate node ACK) -> existing duplicate/custody repair behavior remains; R2 only prevents an unauthenticated receipt from minting delivery.
- Contact/introduction WebSocket authority and generic compatibility getters -> separate feature owners; they do not mint ordinary 1:1 `delivered` in the audited paths.
- Mobile same-LAN smoke -> optional preservation evidence if a fully automated physical-Android plus Android-emulator harness is available; it cannot close spoof resistance and is not a blocker.

Dependencies:

- Plan 336 / R1 is implementation-complete and supplies the only ordinary outgoing settlement authority.
- R3 may assume R2's proof-aware first-commit behavior when aligning Dart/Go deadlines.
- The correctness-wave aggregate `host-all` runs once after R3, not during this individual plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-337-01 | Native sender marks only a top-level semantically affirmative ACK object committed | `go-mknoon/node/send_message_recovery_test.go::TestSendMessageWithTransport_AckFrameValidation` | Go host; two in-process libp2p hosts and table-driven reply frames | HEAD returns `Acked:true` for every readable frame -> only top-level boolean `ack:true` (including whitespace and harmless extra fields) is true; false/missing/wrong-type/malformed/primitive/empty/nested/string-embedded cases are written but uncommitted; the responder asserts the exact request and authenticated remote peer | restore unconditional `Acked:true` or use substring/regex matching -> negative table red | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestSendMessageWithTransport_AckFrameValidation$' -count=1)`; extend `GO_NODE_LIBP2P_REFACTOR_RUN` and its exact batch sentinel, never add a ninth Go invocation |
| TC-337-02 | Under current defaults, receiver recovery custody is durable before Dart confirms and Go ACKs only after positive confirmation | new `p2p_service_impl_test.dart::R2 direct chat and deletion confirm only after durable staging returns`; existing `transport_label_test.go::TestHandleIncomingMessage_DeferredDirectAck_WritesAckAfterConfirm`, `::TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck`, `::TestHandleIncomingMessage_DeferredDirectAck_TimesOutWithoutConfirm`, `::TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce`, `::TestShouldDeferDirectAck_ReactionAndDeletion`; existing `inbox_staging_repository_impl_test.dart::first stage of a fresh entry reports it ackable`; existing `p2p_bridge_client_test.dart::pins exactly the 9 canonical keys with intended polarity` | Dart/Go host; gateable staging repo table for chat/deletion, real SQL-backed staging repo, inbound stream confirm channel, independent Go+Dart defaults | GREEN sentinels on HEAD, with one missing explicit ordering assertion -> the new gated test passes because `message:confirm` is absent while `stageEntries` is parked and occurs exactly once after release; positive confirm writes ACK, false/timeout do not | move Dart confirm before awaited stage, move Go ACK before confirm, or flip either production default -> owning test red | exact three Dart files; native selectors `^TestHandleIncomingMessage_DeferredDirectAck_`, `^TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce$`, and `^TestShouldDeferDirectAck_ReactionAndDeletion$` are run with `GOTOOLCHAIN=go1.25.0 go test ./node -run`; register exact names in `GO_NODE_LIBP2P_REFACTOR_RUN` and at least the false-confirm name in its batch sentinel |
| TC-337-03 | First authenticated libp2p commitment settles immediately; neither 150 ms rank grace nor 120 ms learned head-start can wait for or replace it | `send_chat_message_use_case_test.dart::R2 first authenticated committed ACK settles before virtual transport grace` | Dart host; `fakeAsync`, completer-controlled direct/relay/LAN futures, learned-local and no-learned variants | Direct/learned cases settle after microtasks with no clock advance; relay-first advances only the existing 500 ms scheduling stagger, then settles after microtasks with no additional advance. HEAD remains pending until its extra grace/head-start; GREEN settles while the losing future stays unresolved | restore grace/head-start around a proving result -> direct/learned cases require clock advance and relay-first requires time beyond the scheduling stagger | focused send test; existing 1:1 arrays and feature auto-glob |
| TC-337-04 | A claimed-committed LAN ACK is written-only: it cannot deliver, suppress authenticated work/inbox, or train sticky | `send_chat_message_use_case_test.dart::R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky` | Dart host; durable-LAN fake, controlled direct failure/pending proof, inbox fake, sticky spy | HEAD persists `delivered/local`, skips authenticated/inbox work, or records local -> later direct proof wins; without proof status is `inboxed` or retryable `sent`, exact envelope remains, and local is not learned | mark LAN evidence authenticated or complete on LAN written evidence -> test red | focused send test; existing 1:1 arrays and feature auto-glob |
| TC-337-05 | Written-only ordinary direct/relay race results cannot suppress a later committed live leg | `ranked_race_relay_penalty_test.dart::R2 written direct or relay result cannot suppress later committed live proof` | Dart host; table: direct `acked:false/null` then relay `acked:true`, and relay `acked:false/null` then direct `acked:true`; observer distinguishes leg starts | HEAD lets the first generic success become `best`, suppress or outrank the later leg, or falls inbox -> both legs start as scheduled, the explicit commitment settles with its provenance, and inbox is unused | complete/suppress on any `success`, or rank an uncommitted result above proof -> table red | focused integration file; existing `ONE_TO_ONE_TESTS` and feature auto-glob |
| TC-337-06 | Existing authenticated reuse and learned direct/relay paths short-circuit only on explicit ACK; written/unacked attempts fall through | `send_chat_message_use_case_test.dart::R2 uncommitted reuse and learned routes fall through to authenticated race` | Dart host; queued `SendMessageResult` fake distinguishes the first fast-path write from later race sends | HEAD returns after `sent:true, acked:false` or reply-only legacy result -> explicit ACK keeps one-path fast success, while uncommitted attempts continue and later proof or inbox decides | return on `sent`/`success`, or use `.acknowledged` reply inference at the proof adapter -> test red | focused send test; existing 1:1 arrays and feature auto-glob |
| TC-337-07 | LAN visibility and display label `local` do not imply WebSocket authority | `send_chat_message_use_case_test.dart::R2 LAN-visible authenticated reuse wins and learned local cannot short-circuit proof`; `delete_message_use_case_test.dart::R2 authenticated libp2p ACK may settle with local display label` | Dart host; mDNS-local peer with an existing target-Peer-ID connection; separate WS/libp2p fakes | HEAD bypasses authenticated reuse or equates all local labels with WS -> explicit libp2p ACK settles even if the persisted label remains local; learned WebSocket-local alone falls through | infer authentication from `via == local` or restore the `!isLocalPeer` reuse exclusion -> test red | focused send/delete tests; existing 1:1 arrays and feature auto-glob |
| TC-337-08 | Initial delete reuse/race/relay adapters require explicit authenticated commitment and never hide on written evidence | `delete_message_use_case_test.dart::R2 delete reuse race and relay require explicit authenticated commitment`; `::R2 local delete write waits for pending direct commitment or custody` | Dart host; table over ordinary/private tombstones, reuse/normal-direct/relay-probe `sent:true, acked:null, reply:nonempty`, WS-write-first with a gated direct ACK, explicit-true controls, inbox outcomes | HEAD hides/clears on reply inference or first local success -> reply-only/uncommitted remains visible with envelope and becomes inboxed/sent; no settlement occurs while direct proof is pending; explicit libp2p true may deliver/hide | use `.acknowledged`, hard-code local acknowledged, or complete first generic success -> owning test red | focused delete file; existing 1:1 arrays and feature auto-glob |
| TC-337-09 | Custom failed-delete retry cannot infer delivery from a reply-only result and preserves explicit-ACK success | `retry_failed_messages_use_case_test.dart::R2 failed delete retry requires explicit committed ACK` | Dart host; failed ordinary/private tombstones and exact settlement fake | HEAD maps `sent:true, acked:null, reply:nonempty` to delivered -> reply-only remains `sent` with envelope/visibility; `acked:true` delivers and clears through Plan 336 | use `sendResult.acknowledged` instead of explicit `acked == true` at this minting site -> test red | focused retry test; existing `ONE_TO_ONE_TESTS` registration and feature auto-glob |
| TC-337-10 | Only trusted production ingress provenance may apply a delivery receipt | `handle_delivery_receipt_use_case_test.dart::R2 receipt provenance accepts direct relay inbox and rejects wifi null unknown` | Dart host; table over ordinary, protected/view-once, and deletion rows; the valid inbox case is built through `InboxStagingEntry.toChatMessage`, not a hand-authored label | HEAD applies matching `wifi`/null/unknown receipts -> rejected inputs perform zero row lookup, attachment read, settlement, hide, or envelope clear; direct/relay/inbox apply exactly once and peer mismatch still rejects | remove/widen the allowlist, hand-author the inbox fixture, or place the guard after repository work -> table red | focused receipt file; existing 1:1 arrays and feature auto-glob |
| TC-337-11 | Production ingress, not caller content, assigns receipt identity/provenance | new `transport_label_test.go::TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport`; existing Dart `p2p_service_inbound_transport_test.dart::T2 (NEGATIVE CONTROL): an explicit relay message stays relay`, `::T4: a peer with a live non-circuit connection infers direct`, `::T5: local WiFi messages surface as wifi and are censused`, `::T6: handled LAN commits still record wifi transport telemetry`; existing `go-relay-server/inbox_test.go::TestInboxHandler_ReactionPushBindsAuthenticatedRemotePeer` | Go/Dart host; forged envelope fields over authenticated direct/circuit streams, production local callback, real relay inbox stream with forged `From` | GREEN sentinels on HEAD -> event `from` equals `RemotePeer` and transport equals stream classification despite forged content; existing Dart/relay sentinels retain wifi/direct/relay labels and relay-stored authenticated sender | source `from`/transport from envelope fields, trust WS claimed transport, or retain relay request `From` -> sentinel red | exact Dart file; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport$' -count=1)` registered in `GO_NODE_LIBP2P_REFACTOR_RUN`; `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestInboxHandler_ReactionPushBindsAuthenticatedRemotePeer$' -count=1)` exact existing shared sentinel |
| TC-337-12 | LAN staging/ACK classification remains available but has no final-delivery authority | existing `local_ws_durable_ack_integration_test.dart::receiver killed after committed ack does not lose the message: staged row replays on restart`; existing `local_ws_server_test.dart::withholds ack until inbound commit handler completes and marks it committed`, `::commit handler timeout produces nack not legacy ack`, and `::sendMessageWithAck classifies committed ack, legacy ack, and nack` | Dart host; real loopback WebSocket server/client and staging DB/fake | GREEN sentinels on HEAD -> nonce correlation, committed/legacy/nack classification, and stage-before-ACK remain byte-compatible | remove staging-before-ACK or nonce matching while de-authorizing settlement -> sentinel red | exact two-file command; core auto-glob at later aggregate and exact per-plan command |
| TC-337-13 | Native `acked:false` with a non-empty reply cannot suppress delivery-receipt inbox repair | extend existing `send_delivery_receipt_use_case_test.dart::builds plaintext v1 'delivery_receipt' envelope carrying messageIds and falls back to storeInInbox when live send is unacked` with an explicit-false/non-empty-reply row | Dart host; P2P fake returns `sent:true, acked:false, reply:'forged'` | New GREEN preservation row on HEAD -> one inbox store occurs and result reflects custody | change precedence to non-empty reply over explicit false -> sentinel red | focused named file; existing 1:1 arrays and feature auto-glob |
| TC-337-14 | Plan 336 atomic settlement remains the sole persistence authority and the delivered-minting census remains closed | existing `outgoing_transport_settlement_test.dart::normal settlement enforces the explicit predecessor table without a total rank`, `::first delivered result owns fields across both callback orders`, `outgoing_transport_settlement_writers_test.dart::production wiring and writer census close only the R1 bypass set`, and `delivered_status_minting_sites_test.dart::production code mints status delivered only at the enumerated receiver-confirmation sites` | Dart host; real SQL transaction helper plus exact source/writer census | GREEN sentinels on HEAD -> late written/inbox/failure cannot overwrite first-delivery fields and no new direct minting/persistence writer appears; update stale test comments to describe R2 authority without changing the enumerated counts | bypass typed settlement, restore stale full-row save, or add an unreviewed literal delivered writer -> sentinel red | exact three-file command; registered in curated 1:1/host arrays or feature/core aggregate as documented |
| TC-337-15 | Authority changes preserve relay staggering and message-ID dedup without preserving old winner rank | existing `send_chat_message_use_case_test.dart::FDC-02 relay penalty: when LAN+direct both fail, the staggered relay-live leg still carries` and `::U4 dedup: same messageId across paths persists exactly one row` | Dart host; existing relay observer and fixed message ID fixtures | GREEN sentinels on HEAD -> relay still starts only after its scheduling stagger and duplicate live attempts persist one outgoing row; route winner assertions are updated separately | remove relay stagger or persist a second outgoing row -> relevant sentinel red | focused send file plus curated `1to1`; feature auto-glob |

### Test Notes

- TC-337-02 parks the gateable repository after it has accepted the entry but before `stageEntries` returns. Assert the entry exists and `message:confirm` does not; release the gate, then assert exactly one confirm. Run the real SQL-backed repository sentinel separately so the gateable fake cannot redefine durability.
- TC-337-03 uses `fakeAsync`. For direct-first, complete the proving future, flush microtasks, and assert settlement without advancing the virtual clock. For relay-first, advance exactly the current 500 ms `kRelayLegStagger` so the relay send starts, complete its ACK, flush microtasks, and assert settlement without any additional advance; HEAD remains pending for the extra 150 ms `transportGraceWindow`. Leave the losing future unresolved. For the learned-local case, make its initial short-circuit fail, then let the authenticated direct race leg commit; HEAD buffers that non-learned success for 120 ms, while GREEN settles immediately.
- TC-337-05's direct-first row must make the direct send written/uncommitted before the relay stagger, then advance only the scheduling stagger and return an explicit relay ACK. The relay-first row starts relay as scheduled, leaves direct pending, returns relay uncommitted, then completes direct explicitly.
- TC-337-10 must reject provenance before JSON parsing, `getMessage`, attachment lookup, or settlement. Assert desired telemetry plus absence of every repository mutation so parse failure cannot make the negative case pass accidentally.
- TC-337-01 must prove the responder received the complete request before evaluating `Acked`; otherwise a transport setup failure could make all negative rows pass vacuously.

## Implementation Steps

1. Snapshot `git status --short` and `git diff --cached --name-status`. Preserve Plan 336's staged closure and all unrelated Plan 333/335/index/iOS/notification work; do not stage or rewrite it.
2. Add TC-337-01, the authenticated-ingress sentinel, and the complete TC-337-02 receiver suite first. In `node.go`, add one private affirmative-ACK parser used by `SendMessageWithTransport`; keep raw `Reply` diagnostics, but set `Acked` only for a top-level JSON object with boolean `ack:true`. Add the gateable Dart stage-before-confirm test without changing production staging. Stop-if: the current bridge can omit the explicit `acked` Boolean on the production send-with-reply path.
3. Rewrite the old authority tests and add TC-337-03 through TC-337-07 before Dart production edits. Replace the private chat race's proof-blind success selection with the smallest internal written/committed/authenticated evidence shape. Complete immediately on proof, retain written evidence only for the existing inbox/sent funnel, suppress relay only after proof, and let ordinary-race as well as reuse/sticky uncommitted results fall through. Remove settlement use of `transportGraceWindow`/`kStickyHeadStart`; keep `kRelayLegStagger` scheduling.
4. Make authenticated connection reuse available for LAN-visible peers and prevent learned WebSocket-local from short-circuiting authenticated work. Preserve local WebSocket as a normal, non-authoritative race attempt and telemetry source.
5. Apply the same private proof decision to delete-for-everyone. Require explicit `acked == true` at reuse, normal-direct, relay-probe, and failed-delete-retry minting adapters; a local WebSocket write is never authenticated. Reuse Plan 336 settlement; do not introduce a repository method.
6. Add the fail-closed receipt provenance guard at the top of `handleDeliveryReceipt`, before parsing IDs into repository work. Accept only production-assigned `direct`, `relay`, and `inbox`, then retain the existing peer-ID and atomic settlement checks. Stop-if: source or a production callback proves any accepted label can be supplied unchanged by a local WebSocket payload.
7. Update the stale authority comments in `delivered_status_minting_sites_test.dart`, but keep its exact writer counts. Keep `SendMessageResult.acknowledged`, generic P2P service callers, WebSocket wire frames, deferred-ACK feature-flag behavior, and receipt-send protocol unchanged. Run the exact preservation sentinels after each slice.
8. Extend `GO_NODE_LIBP2P_REFACTOR_RUN` with the ACK parser, authenticated-ingress, and exact deferred-ordering test names. Extend `scripts/test/host_test_gate_batch_contract_test.sh` with exact parser, ingress, and at least one negative-ordering sentinel while retaining exactly eight Go tails. Do not add a ninth synthetic path or change fixed gate counts.
9. Run focused GREEN, mutation re-reds, the local-WebSocket/Plan-336 sentinels, curated `1to1`, the affected `feature-host-all` family, analyzer/format/hygiene, and record semantic results. Full `host-all` remains deferred until R3 closes the R1-R3 correctness wave.

## Risks And Blind Spots

- A result labelled `local` may be either authenticated libp2p over a private address or unauthenticated WebSocket -> TC-337-07 carries authority separately and forbids label inference.
- A forged WebSocket sender can bypass ACK de-authority by injecting a matching delivery receipt -> TC-337-10 closes the independent receipt minting seam.
- A reply-frame negative test could pass because no message was sent -> TC-337-01 asserts the responder received the exact request and returned the selected frame.
- A substring-based ACK parser could accept nested or quoted attacker text -> TC-337-01 includes nested and string-embedded negative frames plus a whitespace-varied top-level positive.
- Go-side wait tests alone do not prove Dart staged durably before confirming -> TC-337-02 gates Dart staging order and pairs it with the real SQL-backed repository sentinel.
- An authenticated but uncommitted direct result could still suppress relay after only LAN is de-authorized -> TC-337-05 covers both direct-first and relay-first written/proving orders.
- Removing grace could accidentally remove relay staggering or dedup behavior -> TC-337-15 keeps scheduling and one-row/message-ID sentinels while intentionally changing winner semantics.
- Lifecycle / derived-state durability: no new persisted marker/cache is introduced; sticky learning is existing in-memory derived state, and TC-337-04/07 proves unauthenticated evidence cannot populate it.
- Sibling-surface consistency: ordinary text/media/edit share `sendChatMessage`; delete initial and custom retry are separately covered by TC-337-08/09. Reactions/contact/introductions do not mint the audited ordinary delivery status and are explicitly preserved/deferred.
- Destructive-action side effects: delete visibility, envelope retention/clearing, ordinary/private tombstone settlement, and unrelated artifact cleanup are asserted in TC-337-08/09; no new cleanup is introduced.
- Invariant re-verification under new transitions: Plan 336 first-delivery freeze and late-custody behavior are rerun in TC-337-14 after the completion order changes.
- Cross-version proof remains limited: older/force-off peers can emit an indistinguishable pre-commit ACK. The plan explicitly accepts current-version/default-on scope rather than pretending a local default test establishes remote capability; mixed-version proof requires a separate protocol decision.

## Gate Cadence

- Per-plan closure: focused Dart causal files; exact Go ACK/ingress/deferred-contract commands; exact relay authenticated-sender, local-WebSocket, staging, and Plan 336 sentinels; `bash scripts/test/host_test_gate_batch_contract_test.sh`; `./scripts/run_test_gates.sh 1to1`; and `./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only` because every changed Dart production file is under `test/features` coverage.
- Do not run full `host-all` for Plan 337. Run `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter failures-only` once after R3 completes the R1-R3 correctness wave, and once at final rollout/release closure after R5.
- Shared tests outside feature globs: run the local-WebSocket, P2P service/default, staging, Plan 336 DB helper, and relay authenticated-sender files by exact command; register all new/current native R2 tests in the existing host-all synthetic selector for the later wave gate.
- No required device/iOS leg: host Dart controls the adversarial decision seam; loopback WebSocket tests exercise the real local protocol; an in-process two-host go-libp2p test exercises real authenticated streams and native frame parsing. A mobile smoke would be supporting preservation only and cannot prove spoof resistance.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated staged/unstaged work.
git status --short
git diff --cached --name-status

# Causal RED 1: native readable-frame bug; expect non-zero on HEAD because
# malformed/negative frames are currently marked Acked=true.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestSendMessageWithTransport_AckFrameValidation$' -count=1)

# Causal RED 2: selector authority; expect non-zero on HEAD because a claimed
# committed LAN result currently suppresses/settles stronger work.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky'

# Causal RED 3: independent forged-receipt bypass; expect non-zero on HEAD
# because wifi/null provenance currently reaches atomic settlement.
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  --plain-name 'R2 receipt provenance accepts direct relay inbox and rejects wifi null unknown'

# Causal RED 4: ordinary-race written result; expect non-zero on HEAD because
# an unacked direct success can suppress the staggered relay proof.
flutter test test/features/conversation/integration/ranked_race_relay_penalty_test.dart \
  --plain-name 'R2 written direct or relay result cannot suppress later committed live proof'

# Causal RED 5: delete authority; expect non-zero on HEAD because local/reply-
# inferred successes can hide the tombstone before authenticated proof.
flutter test test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'R2 delete reuse race and relay require explicit authenticated commitment'

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/integration/ranked_race_relay_penalty_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/send_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/delivered_status_minting_sites_test.dart

# Native GREEN + identity/receiver commitment sentinels; expect all named tests selected.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run 'TestSendMessageWithTransport_AckFrameValidation|TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport|TestHandleIncomingMessage_DeferredDirectAck_|TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce|TestShouldDeferDirectAck_ReactionAndDeletion' \
  -count=1)

# Relay store sender binding; expect forged request.From to be ignored.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestInboxHandler_ReactionPushBindsAuthenticatedRemotePeer$' -count=1)

# Dart stage-before-confirm, production defaults, local protocol, and ingress
# label preservation; expect exit 0.
flutter test \
  test/core/local_discovery/local_ws_server_test.dart \
  test/core/local_discovery/local_ws_durable_ack_integration_test.dart \
  test/core/services/p2p_service_inbound_transport_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/inbox/inbox_staging_repository_impl_test.dart \
  test/core/bridge/p2p_bridge_client_test.dart

# R1 atomic-settlement preservation; expect exit 0.
flutter test \
  test/core/database/helpers/outgoing_transport_settlement_test.dart \
  test/features/conversation/application/outgoing_transport_settlement_writers_test.dart \
  test/features/conversation/application/delivered_status_minting_sites_test.dart

# Synthetic Go host-tail registration; expect unchanged eight-leg contract and
# the R2 ACK test sentinel present.
bash scripts/test/host_test_gate_batch_contract_test.sh

# Curated 1:1 lane and affected feature family; expect exit 0 / zero failures.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene; expect no formatting drift, new analyzer issue, or whitespace error.
dart format --output=none --set-exit-if-changed \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/features/conversation/application/retry_failed_messages_use_case.dart \
  lib/features/conversation/application/handle_delivery_receipt_use_case.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/integration/ranked_race_relay_penalty_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/send_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/delivered_status_minting_sites_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/services/p2p_service_inbound_transport_test.dart \
  test/core/inbox/inbox_staging_repository_impl_test.dart \
  test/core/bridge/p2p_bridge_client_test.dart
test -z "$(gofmt -l \
  go-mknoon/node/node.go \
  go-mknoon/node/send_message_recovery_test.go \
  go-mknoon/node/transport_label_test.go)"
bash -n scripts/run_host_test_gates.sh \
  scripts/test/host_test_gate_batch_contract_test.sh
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-337-01 fails because any readable frame sets `Acked:true`; TC-337-03/04 fail because grace/head-start and LAN claimed commitment outrank proof; TC-337-05 fails because written direct/relay evidence can suppress proof; TC-337-08/09 fail on local/reply-inferred deletion delivery; TC-337-10 fails because receipt provenance is unchecked. TC-337-02/11-15 are explicitly GREEN preservation/coverage sentinels on HEAD.
- Green sentinel: explicit positive libp2p reuse remains fast; local WebSocket still stages before its nonce ACK; Plan 336 settlement refuses late weaker writes; explicit `acked:false` still triggers receipt inbox repair.
- Pre-existing dirty tree / known failure: planning began with Plan 336 staged and a large unrelated notification/iOS/Plan 333/335 working tree. Parallel Flutter baseline startup briefly collided on Flutter's tool lock/native lipo output; the affected baseline tests passed when rerun serially and this is not a product failure.
- Environment blocker: none for host closure. Live inventory on 2026-08-05 included USB Pixel 6 `21071FDF600CSC` and Android emulator `emulator-5554`, but neither is required for the causal authority contract. Unavailable hardware versions are N/A by project policy.
- Scope drift: any need for new wire ACK levels/capability negotiation, WebSocket signing/removal, schema work, deadline changes, inbox hedging, or non-conversation caller refactors blocks this plan and returns that work to its named owner.

- [x] Every behavior has a named test or justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded. Focused/registered GREEN is retained, but a distinct R2 execution RED/mutation ledger was not reconstructed during this cleanup.
- [x] The first authenticated explicit affirmative ACK settles immediately across reuse, sticky, direct, and relay paths under the accepted current-version/default-on contract.
- [x] Dart stages chat/deletion into durable recovery custody before confirming, and Go writes no positive ACK before that confirmation.
- [x] Every local WebSocket result is non-authoritative and cannot deliver, suppress durability/authenticated work, or train sticky success.
- [x] Native ACK parsing rejects every non-affirmative frame while retaining written diagnostics.
- [x] Ordinary/private delete and custom delete retry obey the same explicit-proof boundary.
- [x] Forged `wifi`/null/unknown delivery receipts perform no read-side settlement or destructive cleanup; direct/relay/inbox receipts remain valid.
- [x] Plan 336 atomic settlement and local WebSocket staging/dedup behavior pass unchanged.
- [x] Harness registration preserves the eight-Go-tail host shape and names the parser, authenticated-ingress, and deferred-ordering tests.
- [ ] Focused tests, curated `1to1`, affected `feature-host-all`, analyzer, formatting, and diff hygiene pass. Owned selectors, curated `1to1`, analyzer, formatting, and hygiene are green; the earlier feature-family command retained one isolated group flake that passed twice alone and in full `host-all`.
- [x] No migration or mandatory device/relay proof was introduced.
- [x] Scope Contract And Guard is respected, including the recorded current-version/default-on compatibility limit.

## Handoff

- First causal RED command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestSendMessageWithTransport_AckFrameValidation$' -count=1)`.
- Preservation command: `flutter test test/core/local_discovery/local_ws_server_test.dart test/core/local_discovery/local_ws_durable_ack_integration_test.dart test/core/services/p2p_service_impl_test.dart test/core/inbox/inbox_staging_repository_impl_test.dart test/core/database/helpers/outgoing_transport_settlement_test.dart test/features/conversation/application/outgoing_transport_settlement_writers_test.dart`.
- Manual registration: extend `GO_NODE_LIBP2P_REFACTOR_RUN` with `TestSendMessageWithTransport_AckFrameValidation`, `TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport`, `TestHandleIncomingMessage_DeferredDirectAck_WritesAckAfterConfirm`, `TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck`, and `TestHandleIncomingMessage_DeferredDirectAck_TimesOutWithoutConfirm`; add exact parser, ingress, and false-confirm sentinels to `scripts/test/host_test_gate_batch_contract_test.sh`; preserve the existing selector and aggregate eight-Go-invocation count.
- Migration: none.
- Boundary closure: host-only — controlled/fake-time Dart orchestration, gated stage-before-confirm, real SQL-backed staging, real loopback WebSocket, authenticated Go stream/frame, and relay `RemotePeer` binding tests.
- Unresolved evidence: no current build override forcing deferred ACK off was found; mixed older/force-off peer behavior remains an explicit accepted limitation and is not represented as proven commitment.

## Reviewer Findings

Initial verdict: **plan-fixes-required**. The architecture was viable, but the first draft could pass with partial LAN-only de-authority and overclaimed several existing sentinels.

Required findings applied:

1. Replaced nonce/type-only ACK evidence with the exact positive, false-confirm, and timeout ordering tests; added Dart stage-before-confirm and the load-bearing Dart default.
2. Made zero grace deterministic with `fakeAsync`, unresolved losing futures, microtask settlement, and a failed learned-local short-circuit variant.
3. Added both ordinary-race orders where written-only direct/relay evidence precedes a later explicit commitment.
4. Expanded delete coverage across reuse, normal direct, relay probe, local-write-first concurrency, ordinary/private visibility, and failed-delete retry.
5. Replaced the nonexistent combined provenance test with exact T2/T4/T5/T6 labels, authenticated Go `RemotePeer`/stream classification, `InboxStagingEntry.toChatMessage`, and relay sender binding.
6. Added nested/string-embedded ACK negatives so substring parsing cannot satisfy the semantic JSON contract.
7. Kept the existing eight-Go-tail topology while registering exact parser, ingress, and negative ordering sentinels; added Go formatting hygiene.
8. Replaced the copy-unsafe escaped alternation in TC-337-02 with three executable selectors and made the handoff name every required `GO_NODE_LIBP2P_REFACTOR_RUN` addition and batch sentinel.
9. Made the relay-first zero-grace proof respect the existing 500 ms relay scheduling stagger and fail only on an additional settlement delay.

Five-lens re-audit: evidence/classification, causality, bypass/scope, gate integrity, and boundary/state transitions are clear after the deltas. Evergreen hits B-2, B-4, B-8, B-9, and B-10 are covered by TC-337-02/05/08/10/11 and the explicit compatibility statement; B-1/B-6 are N/A because there is no schema/wire/marker change, and the remaining classes are clear.

Final independent re-review verdict: **READY**. Both reviewers confirmed that the corrected native selectors select real tests, TC-337-03 separates the existing 500 ms relay scheduling stagger from the prohibited additional winner grace, and no required coverage or scope gap remains.

## Arbiter Decision

Verdict: **ready**. Disposition: **execute**.

- Core bet confirmed for current-version/default-on bridge-managed peers: the target-Peer-ID stream authenticates the live responder, the receiver stages into recovery custody before confirm, and only a top-level explicit affirmative ACK is treated as proof.
- The same bytes do not prove commitment from an old or force-off peer. This is retained as an accepted release limitation, not hidden by a local default test. Mixed-version proof would require a separately authorized protocol capability/version change.
- Host closure is sufficient for this plan's deterministic authority boundary. A mobile pair can preserve operations but cannot prove LAN spoof resistance; making it mandatory would add cost without closing a stronger claim.
- Rejected as unnecessary: signed WebSocket ACKs, a new wire ACK level, protocol bump, coordinator/queue, schema migration, native spool, device/iOS closure, deadline/presence/hedge changes, and a ninth Go gate leg.
- Sufficiency result: every in-scope behavior has an honest causal RED or labelled GREEN sentinel, a mutation, a literal gate/registration path, and a bounded scope owner. No required plan delta remains.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-05 21:47 CEST | obsolete authority-harness closure | `transport_switch_learned_invalidation_test.dart`; `f1_wifi_relay_fallback_test.dart`; shared integration fake documentation | Exact two-file run -> `+8`, zero failures; `core-host-all` -> 396 Flutter paths / 3144 tests plus both shell contracts | LAN WebSocket writes remain attempted; authenticated direct/relay proof owns final delivery and sticky learning; 2-write/1-row and 5-write/3-row assertions preserve receiver message-ID dedup | No production change and no blocker; full `host-all` intentionally not repeated | Proceed to R4 using the corrected R2 authority harness |
