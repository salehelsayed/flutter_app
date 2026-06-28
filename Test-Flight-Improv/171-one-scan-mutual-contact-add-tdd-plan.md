# 171 - One QR Scan = Mutual Contact Add (reliable under go-libp2p)  (Bug | Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — user report 2026-06-28 ("one scan should be enough for 2 users to add one another; worked in the old architecture, broke under go-libp2p")

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-28 | Evidence Collector | handle_incoming_message_use_case.dart, contact_request_listener.dart, send_contact_request_use_case.dart, node.go, p2p_service_impl.dart, transport_label_test.go, contact_request_model.dart, accept_and_reciprocate_use_case.dart | 5-agent investigation + 4-agent verify→refute; anchors re-confirmed on new-orbit | — |
| 2026-06-28 | Planner | (this doc) | Design = auto-add v2 + harden go-libp2p delivery (deferred-ack + Dart confirm + staged inbox replay) | hand to RED |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-28 | contract extraction (git status --short) | (snapshot) | dirty = graphify-arch/out + info.plist + this doc only (pre-existing); node.go/lib clean | shared new-orbit tree, 3 other live `claude` sessions + FDC-S4 sim — scoped to own files | RED |
| 2026-06-28 | RED tests added | transport_label_test.go (TC-01/02), handle_incoming_message_use_case_test.dart (TC-05/07/09/10), contact_request_listener_test.dart (TC-03/06/11/12), p2p_service_contact_request_inbox_replay_test.dart NEW (TC-04/14/15/16-B), contact_request_one_scan_mutual_test.dart NEW (TC-08), retry_…_test.dart (TC-16-A) | TC-01/02 RED (`=false want true`; no nonce); TC-05 RED (returns contactRequest) | Expected-RED + mutation-first rows confirmed | impl |
| 2026-06-28 | implementation | node.go (defer contact_request); handle_incoming_message_use_case.dart (+contactAutoAdded enum + v2 auto-add branch after step-8/step-10); contact_request_listener.dart (PUBLIC processIncomingMessage + _maybeConfirmDirectNonce + _routeAutoAdd/_routeToDialog + autoAcceptAndReciprocate/limiter + autoAddedStream); contact_auto_add_rate_limiter.dart NEW; p2p_service_impl.dart (contact_request inbox arm + typedef/field/ctor); main.dart (late contactRequestListener + replay closure + kE2E-gated auto-accept wiring + autoAddedStream) | — | — | GREEN |
| 2026-06-28 | direct GREEN | (above) | Go node+bridge 448s/196s ok + lint 0 + interop reverted; full CR suite +100 host-green | — | preservation |
| 2026-06-28 | preservation GREEN | scripts/run_test_gates.sh + run_host_test_gates.sh (TC-08 arrays) | **1to1 +1387 ALL PASS**; core-host-all PASS; feed 1 flake (`feed_wired_test` TC-162/163 debounce-timing) GREEN isolated +48; analyze 0-new (my files); `git diff --check` clean | feed flake = concurrent-load timing, NOT this change | named gates |
| 2026-06-28 | named gates | integration_test/scripts/run_1to1_device_real.dart (TC-13 scenario) | `--list-scenarios` lists `contact_one_scan_mutual_d1`; `check_reliability_simulation_discovery.sh` exit 0 PASS | TC-13 = manual-two-phone (scenario-only, like fdc11/fdc15 — no integration_test file, FAIL-CLOSED gate intact); device run env-gated/deferred | QA |
| 2026-06-28 | QA (independent) | (read-only review workflow, 5 agents) | deferred-ack + auto-add-security + skeptic 6-case = CLEAN (2s-regression ELIMINATED); inbox BLOCKER (accept-failure silent loss) + wiring MED (late-var tear-off) FOUND + FIXED (dialog fallback + explicit lambda) + new fallback test | host-green complete | TC-13 device-proof (env) |

## Source Of Truth
- Intent: inline below (user report). The "old architecture worked" = the pre-libp2p WebView/JS bridge; the durable `storeInInbox` fallback was actually ADDED during the libp2p migration (`ea2d6598`). There is no removed auto-accept to revert — the receiver accept-dialog has existed since the first feature commit `5dde9dbe`. So this is **make add-contact reliable + tap-free under the new go-libp2p transport**, not a revert.
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md (171 = next free)
- All Go gates under `GOTOOLCHAIN=go1.25.0`; after any Go run revert `go-mknoon/testdata/interop_vectors.json`.

## Session Classification
implementation-ready (host-green achievable now; one device-proof row TC-13 is the closure gate — the 2-phone rig is already provisioned this session).

## Exact Problem Statement
When user A scans user B's QR, A immediately and durably adds B locally and fires a `contact_request` carrying A's full signed contactable info (incl A's ML-KEM key) so B can add A back. This SCANNER-side auto-add is correct and tap-free. **Two bugs break the other half (B adding A):**

1. **Delivery loss under go-libp2p (dominant).** A `contact_request` is NOT in the receiver node's deferred-direct-ack set (`go-mknoon/node/node.go:1625-1642` defers only `chat_message`/`message_reaction`/`message_deletion`; everything else hits `default: return false`). So the receiver's libp2p node writes `{"ack":true}` on byte-receipt (`node.go:1779-1786`) **before** the Dart app has processed the message. A freshly-installed B is still cold-starting, so `IncomingMessageRouter`/`ContactRequestListener` (`main.dart:3120-3121`) are not yet subscribed to the **unbuffered broadcast** `messageStream` (`p2p_service_impl.dart:177`, `_emitIncomingMessage:1278`). The request is emitted with no subscriber → silently dropped. Because A got `acked=true`, `sendContactRequest` returns success (`send_contact_request_use_case.dart:281-301`) and **never** writes the durable relay-inbox fallback (`:320-332`, reached only on direct FAILURE). **Recovery EXISTS but is itself defeated by the same drop:** the QR omits ML-KEM (`build_qr_payload:55`) so A's scanned B has `mlKemPublicKey==null` (`contact_model.dart:93`), which makes B eligible for `retryIncompleteKeyExchanges` (`:61`, re-calls `sendContactRequest` `:79`) on app-resume (`handle_app_resumed.dart:537` Step 4) + the periodic `key_exchange_retrier`. So the loss is RECOVERABLE in principle — BUT every re-send hits the SAME cold-receiver immediate-ack drop until this plan's deferred-ack + staged-replay land, so a still-cold B keeps losing it. → effectively lost until B happens to be live-subscribed at a retry; B never sees a dialog meanwhile. (Real-world repro: this session, iPhone 13 scanned iPhone 11's QR; iPhone 11 never got the request.) See **Offline / No-Relay Handling** below for how the fix makes this eventually-consistent.

2. **Consent gate (when delivery does succeed).** `handle_incoming_message_use_case.dart:387-399` parks a verified new request as `status=pending` and returns `HandleMessageResult.contactRequest`; the listener surfaces a modal `ContactRequestDialog`. B must physically tap Accept (→ `acceptAndReciprocateContactRequest`) to add A + send B's reciprocal. The crypto/data already supports a tap-free add (the request is a superset of the QR incl ML-KEM; precedent: `recover_intro_contact_request_use_case.dart:158-189` silently auto-adds from an identical verified envelope).

**What must improve:** one scan reliably results in **both** users as mutual contacts under go-libp2p, with **zero taps** on the scanned side, even when the scanned device just came online.

**What must stay unchanged (→ preserved-green sentinels):** chat/reaction/deletion deferred-ack behavior; introduction flow; v1-plaintext requests stay on the manual-accept dialog (no auto-add); `EnableDeferredDirectAck` default stays `true`; existing `handle_incoming_message_use_case_test.dart` ~60 assertions; the 1:1 and feed reliability gates.

## Root Cause (verify → refute confirmed)
- **Delivery:** `node.go:1625-1642` `shouldDeferDirectAck` excludes `contact_request` → immediate ack masks non-delivery to a cold receiver whose listener (broadcast, `p2p_service_impl.dart:177/1278`, wired `main.dart:3120-3121`) is not yet subscribed; sender's success short-circuit (`send_contact_request_use_case.dart:281-301`) skips the durable inbox. SECONDARY: even via inbox, `contact_request` has no staged-until-committed arm in `_replayStagedInboxEntries` (generic emit+immediate `deleteEntry` at `p2p_service_impl.dart:1517-1521`; contrast intro arm `:1414-1444`).
- **Consent:** `handle_incoming_message_use_case.dart:387-399` parks pending → dialog; only a manual tap adds + reciprocates.

**Verified-mandatory companion (the trap):** adding `contact_request` to the Go deferred set **alone REGRESSES** — the deferred path blocks `DirectConfirmTimeout=2s` (`config.go:95`) waiting for a Dart `message:confirm` (`ResolveDirectConfirm` `node.go:1687`); `EnableDeferredDirectAck` defaults `true` (`feature_flags.go:82`). `ContactRequestListener` has **no confirm path today** (`grep confirmDirect` in the feature dir = 0). Without a Dart confirm, every direct contact_request times out → stream reset → sender always falls to inbox (+2s). The fix MUST add a listener confirm mirroring `introduction_listener._maybeConfirmDirectNonce` / `chat_message_listener._maybeConfirmDirectNonce:331-350`. `_emitIncomingMessage:1278` passes the message unmodified so `confirmNonce` reaches the listener intact; the listener already holds a `bridge` field.

Refuted / do-NOT-re-introduce:
- "Old architecture auto-added mutually and a refactor removed it" — **REFUTED** (git: dialog present since `5dde9dbe`; auto-accept only ever in `smoke_test_runner.dart`). Frame as new feature, not revert.
- "Editing `handle_scanned_qr_use_case.dart` changes scan behavior" — **REFUTED**: that use case is ORPHANED (only its own test references it). The LIVE scan path is inlined in `qr_scanner_wired.dart:245-256,283`. (No scan-SIDE change is needed for this fix anyway.)
- "Adding `HandleMessageResult.contactAutoAdded` breaks switch fakes" — **REFUTED**: zero `switch` over the enum anywhere; consumed via `==` chains (`contact_request_listener.dart:198-256`). It's a return enum, not an interface → no fakes break.
- "block-check needs a new `ContactRepository.isBlocked()`" — **REFUTED**: block state is readable via existing `getContact(peerId).isBlocked` (`contact_model.dart:44`); `handleIncomingMessage` already calls `getContact` at `:322`. Keep the fix off the `ContactRepository`/`P2PService` interfaces (avoids the 28-/33-fake cascade, [[reference_p2pservice_interface_addition_breaks_all_fakes]]).
- "isBlocked covers resurrection" — **REFUTED/HOLE**: a **declined** request (`decline_contact_request` sets `status=declined`) is NOT short-circuited by step-9 (`:376-385` checks only `status==pending`) and a declined peer has **no contact row**, so `isBlocked` can't catch it. A `status==declined` guard is mandatory.

## Offline / No-Relay Handling  (added per review 2026-06-28 — "two users add each other with no internet")
Three sub-cases; the design must be EXPLICIT about each (none was stated in the draft):

1. **Both users scan each other (mutual scan), fully offline.** ✅ Works with ZERO network. Each scanner's `addContact` (`qr_scanner_wired.dart:245`) is a local SQLCipher write from the QR payload — no node, no relay. Both end up with each other's contact row immediately. Caveat: the QR omits ML-KEM, so PQ-key exchange completes later (on connectivity, via the resume-retry below); the contact relationship + classical messaging exist offline. **This is the most robust offline path** (and why mutual-scan was the earlier workaround).

2. **One scan, same local Wi-Fi but no internet** (LAN router with no upstream, or peer-to-peer Wi-Fi). ⚠️ Delivers over the LAN IF: bonsoir/mDNS discovers the peer (multicast — works without internet) AND a LAN delivery leg succeeds — the legacy WS-LAN `sendLocalMessage` (`send_contact_request_use_case.dart:232-249`, `isLocalPeer`) OR libp2p LAN-direct (`:261-301`, gated by FDC-11 `EnableLibp2pLANDial`, currently dark). When the LAN leg delivers, B receives the request and (with this plan) auto-adds. Residual: timing — if discovery hasn't completed at scan time, the first send fails all legs; recovery is the resume-retry (below).

3. **One scan, truly offline** (no shared network, no relay). At scan time all three legs fail → `sendFailed` (`:341`, just returned). The request is NOT delivered. **Recovery = the existing `mlKemPublicKey==null`-as-outbox retry**: A's scanned B has null ML-KEM → eligible for `retryIncompleteKeyExchanges` (`:61`) → re-`sendContactRequest` (`:79`) on app-resume (`handle_app_resumed.dart:537`) + the periodic `key_exchange_retrier`. When A regains ANY connectivity (LAN or relay), the re-send delivers → B auto-adds + reciprocates (B's reciprocal carries B's ML-KEM → A's B row gets ML-KEM → no longer eligible → retry stops, self-limiting). → **eventually consistent**, NOT permanent loss.

**Why this plan is REQUIRED for the offline story (not just the cold-install story):** every re-send from the retry hits the SAME cold-receiver immediate-ack drop on HEAD. The deferred-ack + Dart confirm (legs a/step-5) + staged inbox-replay (step-8) make each (re-)delivery actually land on a not-yet-subscribed B. So the existing retry + this plan together = offline-robust; neither alone is.

**No new outbox/migration needed:** the `mlKemPublicKey==null` contacts row already IS the durable outbound queue for QR contacts (mirrors the dedicated `introduction_outbox`, migration 047, which exists for introductions). Adding a separate `contact_request_outbox` would duplicate it — explicitly OUT of scope (recorded in Accepted Differences). The ONE thing missing is a TEST locking that a QR contact (null ML-KEM) re-sends on resume AND that the re-sent request lands on a cold B → **TC-16**.

## Real Scope
**In scope:**
- Go: add `contact_request` to `shouldDeferDirectAck` (`node.go:~1631`) + fix the stale comment; update `transport_label_test.go:499`.
- Dart receiver confirm: add `_maybeConfirmDirectNonce`-style confirm to `ContactRequestListener` (fires `callP2PConfirmDirectMessage(nonce, ok)` after `handleIncomingMessage` returns; ok=true on any returned result, ok=false only on thrown error).
- Dart auto-add: in `handle_incoming_message_use_case.dart`, for a NEW, v2-encrypted, verified request passing guards → store pending (audit) + return new `HandleMessageResult.contactAutoAdded`; keep v1 / guard-failed on `contactRequest` (dialog).
- Guards: `status==declined` guard + defensive `getContact().isBlocked` guard before auto-add; route ML-KEM through the existing anti-rollback `contactKeyUpdated` path.
- **Extract a public `ContactRequestListener.processIncomingMessage(ChatMessage) -> Future<HandleMessageResult>`** (refactor; chat + intro listeners already did this — `main.dart:2039/2054/2218` reuse `processIncomingMessage` from their inbox callbacks). Today the full receive logic is in the **private void** `_onMessage` (`:172`), so the inbox-replay path CANNOT invoke auto-add/reciprocal/confirm. Make `_onMessage` delegate to the new public method, and wire the new inbox arm to the SAME method (so the cold-B inbox path runs identical logic).
- Dart listener routing: on `contactAutoAdded` → call `acceptAndReciprocateContactRequest(peerId)` (one add + reciprocal) + emit a NON-MODAL `CONTACT_AUTO_ADDED` notice (with block/undo affordance) INSTEAD of `_requestController.add`; add `contactAutoAdded` to the replay-cache OR-list (`:198-202`). This logic lives in the public `processIncomingMessage` so BOTH the live broadcast path and the inbox-replay path produce the auto-add + reciprocal.
- Dart inbox durability: staged-until-committed arm for `contact_request` in `_replayStagedInboxEntries` + `_replayRecoveredInboxContactRequest` callback that calls `contactRequestListener.processIncomingMessage(...)` (mirror chat/intro `main.dart:2039/2218` + `p2p_service_impl.dart:1414-1444`), wired from `main.dart`. **Terminal-result → committed mapping MUST include `contactAutoAdded` AND `contactRequest`** (the two most common new-request outcomes) alongside `alreadyContact/duplicateRequest/invalidMessage/silentIntroRecovered`; only a thrown error → retryable. Omitting `contactAutoAdded`/`contactRequest` would treat every drained new request as retryable → re-replay → re-auto-add/re-reciprocate (violates INV-6).
- Rate-limit: small in-process per-peer/global auto-add limiter (net-new util; in-memory).
- kE2ETestMode coherence: auto-add must respect `kE2ETestMode` suppression (`main.dart:2300-2302,3606-3608`) and not break `smoke_test_runner.dart` `auto_accept`.

**Out of scope (owners):**
- QR-nonce co-presence binding (stricter anti-spam) → follow-on (user picked "auto-add v2" not "QR-nonce"). Named here as Accepted Difference.
- `send_contact_request_use_case.dart` "always-inbox on success" (belt-and-suspenders leg b) → **deferred/likely-unneeded**: deferred-ack (leg a) already routes a cold receiver to the durable inbox; always-inbox doubles relay traffic. Tracked as Accepted Difference; revisit only if device evidence shows a gap.
- Flipping any prod transport flag (FDC CV-08/09) → owned by the FDC Phase-4 device campaign.
- Persistent (cross-restart) rate-limit → in-memory is sufficient for spam mitigation; persistence would need a DB migration, deferred.

## Files To Inspect Next
Production: `go-mknoon/node/node.go` (`shouldDeferDirectAck:1625`, deferred path `:1734-1776`), `lib/features/contact_request/application/handle_incoming_message_use_case.dart` (`:13-34` enum, `:97/177/219` v2/v1, `:319/322` getContact, `:376-399` step9/10), `lib/features/contact_request/application/contact_request_listener.dart` (`:172-266`, `bridge` field `:157`, ReplayCache `:21-56`), `lib/core/services/p2p_service_impl.dart` (`:1071-1131`, `:1343/1414-1444/1517-1521`), `lib/features/contact_request/application/accept_and_reciprocate_use_case.dart` (`:21,32,39,78-93`), `lib/features/contact_request/domain/models/contact_request_model.dart` (`:58-69,122-132`), `lib/main.dart` (`:2307-2327` listener construction, `:3120-3121` start).
Direct tests + integration: `test/features/contact_request/application/{handle_incoming_message_use_case,contact_request_listener,accept_and_reciprocate_use_case,accept_contact_request_use_case,send_contact_request_use_case}_test.dart`, `test/features/contact_request/integration/contact_request_flow_test.dart`, `go-mknoon/node/transport_label_test.go` (`:412,:479-507,:306`).
Dependency-only context: `lib/core/services/incoming_message_router.dart:172`, `lib/features/conversation/application/chat_message_listener.dart:331-350`, `lib/features/introduction/.../introduction_listener.dart` `_maybeConfirmDirectNonce`, `lib/core/bridge/p2p_bridge_client.dart:1415` (`callP2PConfirmDirectMessage`). **Do NOT edit `lib/core/services/contact_request_listener.dart` (hollow stub).**

## Existing Tests Covering This Area
- `handle_incoming_message_use_case_test.dart` — covers every `HandleMessageResult` via `expect(equals(...))` (~60 sites); has inline `implements ContactRepository` + `implements P2PService` fakes. (exists; extend)
- `contact_request_listener_test.dart` — listener routing; `implements ContactRepository`; sets `flowEventLoggingEnabled=false`. (exists; extend — first flow-sink capture in this dir needed for TC-06/TC-11)
- `accept_and_reciprocate_use_case_test.dart`, `accept_contact_request_use_case_test.dart`, `send_contact_request_use_case_test.dart` — accept/reciprocal/send. (exists; preserve)
- `transport_label_test.go:407-507` — DirectAck confirmNonce contract + `{"contact_request",false}`. (exists; TC-01/TC-02 edit)
- `contact_request_flow_test.dart` (integration, OPTIONAL_MANUAL) — end-to-end. (exists; extend for TC-08)
MISSING: any confirm-path test on the Dart side (0 `confirmDirect` refs in the feature dir); any staged-inbox-replay test for contact_request; any declined-resurrection / rate-limit / auto-add test; the device-proof.
Already in curated arrays?: `handle_incoming_message_use_case_test` + `contact_request_listener_test` are in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:64,67`) AND `ONE_TO_ONE_HOST_TESTS` (`run_host_test_gates.sh:48,51`) → new assertions auto-run in `1to1`. New files must be hand-added to those arrays.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `go-mknoon/node/transport_label_test.go::TestShouldDeferDirectAck_ReactionAndDeletion` (edit `:499`)
   - Tier: Go unit. Shape: flip the table row `{"contact_request", false}` → `{"contact_request", true}`.
   - RED on HEAD because: HEAD `shouldDeferDirectAck` returns false for `contact_request`.
   - GREEN asserts: `contact_request` is deferred. Mutation: remove the `case "contact_request"` → red.

2. `go-mknoon/node/transport_label_test.go::TestHandleIncomingMessage_ContactRequest_AttachesConfirmNonce` (new, mirror `:412` DirectAck contract)
   - Tier: Go unit. Shape: a direct `contact_request` envelope with `EnableDeferredDirectAck=true` → response frame carries a `confirmNonce` and the node waits (no immediate `{"ack":true}` until `ResolveDirectConfirm`).
   - RED on HEAD: HEAD acks immediately, no nonce. GREEN: nonce attached + ack deferred. Mutation: revert the switch case → red.

3. `test/features/contact_request/application/contact_request_listener_test.dart::confirms deferred contact_request after commit`
   - Tier: unit/application (host). Shape: feed a `ChatMessage` with `confirmNonce` set; `FakeBridge` records `confirmDirectMessage(nonce, ok)`. Assert: after `handleIncomingMessage` returns, listener calls confirm `ok:true`; with `confirmNonce==null` → NO confirm call; when `handleIncomingMessage` throws → `ok:false`.
   - RED on HEAD: listener never calls confirm (0 refs). GREEN: confirm fired per mapping. Mutation: delete the confirm call → red.
   - Distinct-event discriminator: assert `CONFIRM_DIRECT{ok:true}` AND NOT a second emission.

4. `test/core/services/p2p_service_contact_request_inbox_replay_test.dart::drained contact_request DURABLY PERSISTS before deleteEntry` (new)
   - Tier: integration (host, RECORDING fake request/contact repo + recording inbox-staging repo). Shape: stage a `contact_request` inbox entry, drain it. Assert: a real `requestRepo.addRequest(...)` **and/or** `contactRepo.addContact(...)` write is OBSERVED on the recording fake BEFORE `repo.deleteEntry(...)` is called (ordering captured by a shared call-log). With the arm reverted, `deleteEntry` runs with NO preceding write (row lost).
   - RED on HEAD: generic fall-through (`p2p_service_impl.dart:1517-1521`) emits then immediately deletes → no durable write before delete. GREEN: staged arm persists first. Mutation: revert the `_replayStagedInboxEntries` arm → red.
   - Discriminator: assert the recorded **write call** precedes the **delete call** in the call-log (a flow event alone is NOT accepted as proof of persistence).

5. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart::v2 new request returns contactAutoAdded`
   - Tier: unit/application. Shape: a NEW (non-contact) v2-encrypted verified request → `result == HandleMessageResult.contactAutoAdded`, request row stored pending (audit).
   - RED on HEAD: HEAD returns `contactRequest`. GREEN: `contactAutoAdded`. Mutation: revert the v2 auto-add branch → returns `contactRequest` → red.

6. `test/features/contact_request/application/contact_request_listener_test.dart::contactAutoAdded auto-accepts + reciprocates + confirms, no dialog`
   - Tier: unit/application. Shape: stub `handleIncomingMessage` → `contactAutoAdded` for a message WITH `confirmNonce` set; `FakeBridge` records `confirmDirectMessage`. Assert, IN ORDER, EXACTLY ONCE EACH: (a) `acceptAndReciprocateContactRequest(peerId)` fires, THEN (b) `callP2PConfirmDirectMessage(nonce, ok:true)` fires; AND `CONTACT_AUTO_ADDED` notice emitted; AND NOT added to `_requestController` (no dialog).
   - RED on HEAD: no `contactAutoAdded` branch → falls through, no auto-accept, no confirm. GREEN: auto-accept + confirm(ok:true) + notice + no dialog. Mutation: revert the listener branch → red; SEPARATE mutation: make the `contactAutoAdded` branch `return` before the shared confirm → the confirm-fires assertion flips red (guards against the 2s-timeout-on-the-happy-path regression finding #6).
   - Discriminator: assert `CONTACT_AUTO_ADDED` AND `confirmDirectMessage{ok:true}` AND NOT the request-dialog stream emission.

7. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart::v1 plaintext new request stays on dialog (not auto-added)`
   - Tier: unit/application. Shape: a NEW v1 plaintext verified request → `result == contactRequest` (pending→dialog), NOT `contactAutoAdded`.
   - RED on HEAD: trivially passes on HEAD (already contactRequest) → **mutation-first**: this is a guard-lock; its RED is proven by the mutation "drop the `version=='2'` gate so v1 also auto-adds → this test flips RED". GREEN (post-fix): v1 stays `contactRequest`.

8. `test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart::B fresh auto-adds A and reciprocates; A no loop; one row each` (new)
   - Tier: integration (two `FakeP2PService` over a fake net + real SQLCipher in setUp). Shape: A scans B (A pre-adds B + sends v2 request); B cold; assert B ends with exactly one A contact (no tap) + a reciprocal reaches A; A (already a contact) returns `alreadyContact` and does not re-reciprocate; both have exactly one contact row.
   - RED on HEAD: B parks pending, never adds without a tap → B has 0 contacts. GREEN: mutual, one row each. Mutation: revert auto-add branch → B 0 contacts → red.

9. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart::declined request is NOT resurrected by auto-add`
   - Tier: unit/application. Shape: an existing `contact_requests` row `status=declined` for peer A; a new v2 request from A arrives → must NOT auto-add (returns `contactRequest`/dialog or a no-op result), and must NOT add A as a contact.
   - RED-via-mutation (PASSES on pristine HEAD — HEAD has no auto-add, so a declined peer already falls to `contactRequest`/dialog with no add): the RED is the mutation "implement auto-add WITHOUT the `status==declined` guard" → step-9 (`pending`-only) lets a declined peer through → auto-adds (resurrection) → red. GREEN (post-fix): declined guard keeps it on the dialog path, no add. (Categorized mutation-first, NOT Expected-RED — audit finding #3.)

10. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart::blocked peer is NOT auto-added`
    - Tier: unit/application. Shape: A already a contact with `isBlocked=true`; a new v2 request → returns `alreadyContact` (step-8 short-circuit), never `contactAutoAdded`, no reciprocal.
    - RED-via-mutation: locks the invariant; mutation "remove the defensive block guard AND move auto-add ahead of step-8" → red. GREEN: blocked stays `alreadyContact`.

11. `test/features/contact_request/application/contact_request_listener_test.dart::auto-add rate-limit caps then falls back to dialog`
    - Tier: unit/application (inject a fake clock/limiter). Shape: N+1 auto-add-eligible requests from distinct peers within the window → first N auto-add, the rest fall back to `contactRequest`/dialog (not silently dropped).
    - RED on HEAD: no limiter → all auto-add. GREEN: capped. Mutation: revert the limiter → all auto-add → red.

12. `test/features/contact_request/application/contact_request_listener_test.dart::same-msgId v2 delivered twice → exactly one auto-accept/reciprocal` (RE-TIERED to the LISTENER — finding #2)
    - Tier: unit/application (LISTENER, not use-case). Shape: deliver the SAME v2 `msgId` twice through `processIncomingMessage` (the real listener, so the real `_replayCache` `:209` is populated after the first); assert `acceptAndReciprocateContactRequest` and the reciprocal fire EXACTLY ONCE total.
    - RED-via-mutation: mutation "omit adding `contactAutoAdded` to the replay-cache OR-list `:198-202`" → the msgId never enters `_replayCache` → the 2nd delivery re-runs auto-add → TWO reciprocals → red. (The old use-case-test form was VACUOUS: it seeded `seenMessageIds` directly and tested the PRE-EXISTING `:127` dedup, which the omission mutation cannot affect.)
    - Note: a use-case-level `seenMessageIds`→`invalidMessage` test still exists as a PRESERVATION sentinel (pre-existing dedup unchanged), but it does NOT lock INV-6 — this listener test does.

13. `integration_test/contact_one_scan_mutual_proof_test.dart::one scan mutually adds both, both OS, no duplicate` (new — CLOSURE GATE)
    - Tier: device-proof (2 real phones, real `GoBridgeClient`, real relay, `@Tags(['device'])`). Shape: A scans B's QR with B freshly installed; assert B auto-adds A with **zero taps** + reciprocal reaches A; both phones show exactly one contact row; no duplicate rendered. Verify via `[FLOW]`: `QR_HANDLE_SCANNED_REQUEST_SENT`(A) correlated to `CONTACT_AUTO_ADDED`(B) + `RECIPROCAL_CONTACT_REQUEST_RESULT`(B→A).
    - RED on HEAD: B never adds A without a tap. GREEN: tap-free mutual on real go-libp2p. PROD-CRITICAL: this is the only row that proves the wire/transport leg end-to-end; host coverage is NOT sufficient on its own.

14. `test/core/services/p2p_service_contact_request_inbox_replay_test.dart::cold-B inbox path auto-adds + reciprocates before deleteEntry` (new — HOST CLOSURE FOR THE DOMINANT BUG, finding #1)
    - Tier: integration (host, real `ContactRequestListener.processIncomingMessage` wired to the inbox arm + recording fakes). Shape: drain a NEW v2 `contact_request` for a cold B (live broadcast had NO subscriber). Assert the inbox arm runs the FULL processing: a durable A-contact row is written AND `RECIPROCAL_CONTACT_REQUEST_RESULT`(B→A) is emitted, BOTH before `deleteEntry`.
    - RED on HEAD (and on a naive "mirror-intro arm that only calls `handleIncomingMessage`"): the request is committed-and-deleted but the contact row stays absent and NO reciprocal fires → cold B not mutual. GREEN: inbox path reaches mutual via the extracted public `processIncomingMessage`. Mutation: route the inbox arm to `handleIncomingMessage` directly (bypassing the listener) → no reciprocal/no add → red.
    - Why it exists: TC-08 (fake net) delivers to B's LIVE listener and never exercises the inbox arm; TC-04 only asserts persist-before-delete. This is the ONLY host test that the cold-B (dominant-bug) recovery is actually mutual.

15. `test/core/services/p2p_service_contact_request_inbox_replay_test.dart::after restart (empty replay cache) a redelivered v2 request does NOT re-auto-add/re-reciprocate` (new — durable dedup, finding #7)
    - Tier: integration (host, real SQLCipher contact row already present, FRESH listener with empty in-memory `_replayCache`). Shape: A already a durable contact; redeliver the same/another v2 request from A (e.g. relay re-pushes on reconnect) → assert `alreadyContact` path → NO second `addContact`, NO reciprocal.
    - RED-via-mutation: locks that dedup survives a remount via the DURABLE contact row (not the volatile `_replayCache:209`). Mutation: make the auto-add branch run BEFORE step-8 `contactExists` (`:319-320`) → a redelivered request re-adds + re-reciprocates → red.
    - Discriminator: assert `addContact` call-count == the pre-existing 0 (no new write) AND reciprocal send-count == 0.

16. `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart::offline-scanned contact (null ML-KEM) re-sends contact_request on retry` + `test/core/services/p2p_service_contact_request_inbox_replay_test.dart::re-sent request lands on a cold B → auto-add` (NEW — offline eventual-consistency, review 2026-06-28)
    - Tier: unit/application (retry eligibility) + integration (cold-B landing). Shape A: a QR contact with `mlKemPublicKey==null` (and the original send `sendFailed`) → `retryIncompleteKeyExchanges` includes it and calls `sendContactRequest` again. Shape B: the re-sent request, arriving at a still-cold B, is durably staged + auto-adds (reuses the TC-04/TC-14 path).
    - RED on HEAD: Shape A passes on HEAD (eligibility pre-exists) → **mutation-first** (mutation: set the QR-contact's ML-KEM non-null so it's excluded → retry skips it → assert-included reds), guarding the "QR-contact-is-eligible" invariant the draft got WRONG. Shape B is RED on HEAD (cold B drops the re-send) and GREEN after the deferred-ack/staged-replay land.
    - Why: locks that the offline one-scan case is eventually consistent (resume/periodic retry re-sends AND the re-send actually lands on a cold B). Without Shape B, "recovery exists" is theater (every retry re-drops).
    - Distinct-event discriminator: `KEY_EXCHANGE_RETRY{count}` includes the peer AND a later `CONTACT_AUTO_ADDED` for the same peer from the inbox path.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 defer ack | Go branch logic | Go unit | transport_label_test.go::TestShouldDeferDirectAck_ReactionAndDeletion | HEAD false for contact_request | remove `case "contact_request"` | `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./node/ -run TestShouldDeferDirectAck` | AUTO (go test ./node/) |
| TC-02 nonce contract | Go deferred-ack wire | Go unit | transport_label_test.go::TestHandleIncomingMessage_ContactRequest_AttachesConfirmNonce | HEAD acks immediately, no nonce | revert switch case | `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./node/ -run ContactRequest_AttachesConfirmNonce` | AUTO |
| TC-03 Dart confirm | listener→bridge confirm mapping | unit/application | contact_request_listener_test.dart::confirms deferred contact_request after commit | listener never confirms (0 refs) | delete confirm call | `flutter test test/features/contact_request/application/contact_request_listener_test.dart` | AUTO + already in ONE_TO_ONE arrays |
| TC-04 inbox durability (real persist) | staged write-before-delete | integration (host) | test/core/services/p2p_service_contact_request_inbox_replay_test.dart::DURABLY PERSISTS before deleteEntry | generic emit+delete, no durable write before delete | revert replay arm | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/**) |
| TC-14 cold-B inbox mutual | inbox path → add+reciprocal | integration (host) | test/core/services/p2p_service_contact_request_inbox_replay_test.dart::cold-B inbox path auto-adds + reciprocates before deleteEntry | naive mirror-intro arm commits+deletes but no add/reciprocal | route inbox arm to handleIncomingMessage directly (bypass listener) | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/**) |
| TC-15 restart dedup | durable-row dedup | integration (host) | test/core/services/p2p_service_contact_request_inbox_replay_test.dart::redelivered v2 after restart not re-added | mutation (auto-add before step-8) | move auto-add ahead of step-8 contactExists | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/core/**) |
| TC-05 auto-add v2 | result branch | unit/application | handle_incoming_message_use_case_test.dart::v2 new request returns contactAutoAdded | HEAD returns contactRequest | revert v2 auto-add branch | `flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-06 listener auto-accept | routing + notice + confirm-in-order | unit/application | contact_request_listener_test.dart::contactAutoAdded auto-accepts + reciprocates + confirms, no dialog | no branch → falls through (no auto-accept, no confirm) | revert listener branch; OR `return` before shared confirm → confirm-fires assertion reds | `flutter test …/contact_request_listener_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-07 v1 stays dialog | security gate | unit/application | handle_incoming_message_use_case_test.dart::v1 plaintext stays on dialog | mutation-first (drop v2 gate) | drop `version=='2'` gate | `flutter test …/handle_incoming_message_use_case_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-08 mutual convergence | two-party, real DB | integration | test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart::B fresh auto-adds A, one row each | B never adds without tap | revert auto-add branch | `./scripts/run_test_gates.sh 1to1` | **add to ONE_TO_ONE_TESTS + ONE_TO_ONE_HOST_TESTS arrays** |
| TC-09 declined guard | resurrection safety | unit/application | handle_incoming_message_use_case_test.dart::declined NOT resurrected | naive auto-add resurrects | revert declined guard | `flutter test …/handle_incoming_message_use_case_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-10 blocked guard | abuse safety (defense-in-depth; step-8 is primary) | unit/application | handle_incoming_message_use_case_test.dart::blocked NOT auto-added | step-8 contactExists→alreadyContact already catches blocked (guard is dead unless ordering changes) | COMPOUND: move auto-add ahead of step-8 AND remove the in-branch isBlocked guard | `flutter test …/handle_incoming_message_use_case_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-11 rate-limit | amplification safety | unit/application | contact_request_listener_test.dart::rate-limit caps then dialog | no limiter → all auto-add | revert limiter | `flutter test …/contact_request_listener_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-12 replay dedup | idempotency (LISTENER, re-tiered) | unit/application | contact_request_listener_test.dart::same-msgId v2 twice → exactly one auto-accept/reciprocal | listener `_replayCache` not populated for contactAutoAdded → 2nd delivery re-runs | omit cache OR-list `:198-202` | `flutter test …/contact_request_listener_test.dart` | AUTO + ONE_TO_ONE arrays |
| TC-13 device-proof | multi-device + real relay + real crypto | device-proof | integration_test/contact_one_scan_mutual_proof_test.dart::one scan mutual both OS | B never adds without tap on real libp2p | revert auto-add branch | `/sims 1to1 --only N` (after `check_reliability_simulation_discovery.sh`) | **classify_path case + run_1to1_device_real.dart `--scenario contact_one_scan_mutual_d1`** |
| TC-16 offline eventual-consistency | retry re-send + cold-B landing | unit/application + integration | retry_incomplete_key_exchanges_use_case_test.dart::null-MLKEM QR contact re-sends + p2p_service_contact_request_inbox_replay_test.dart::re-sent lands on cold B | A: mutation-first (set ML-KEM non-null → excluded); B: cold B drops the re-send on HEAD | A: make QR-contact ML-KEM non-null; B: revert deferred-ack/staged-replay | `flutter test test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart ; ./scripts/run_host_test_gates.sh core-host-all` | AUTO (test/features/** + test/core/**); retrier test already in ONE_TO_ONE arrays |

## Blind-Spot Sweep  (evergreen)
- **Lifecycle / derived-state durability:** TC-04/TC-14 cover cold-start durability + mutual recovery from the relay inbox; **TC-15 explicitly covers fresh-mount: an empty in-memory `_replayCache` after restart must NOT cause a re-auto-add/re-reciprocate — dedup falls back to the DURABLE contact row (step-8), not the volatile cache** (this was the audit's finding #7). The rate-limit state is in-memory by design (resets on restart) — justified N/A for persistence (a fresh process resetting the limiter is acceptable; the spam window is per-session). The auto-add writes a durable contact row (no derived-only state); the only volatile derived state (`_replayCache`) is now backstopped by TC-15.
- **Sibling-surface consistency:** the auto-add gate (`version=='2'` + not-declined + not-blocked + rate-limit) is a RECEIVE-path policy; the parallel surfaces are the OTHER `HandleMessageResult` producers (`alreadyContact`/`contactKeyUpdated`/`silentIntroRecovered`). TC-09/TC-10/TC-12 lock that auto-add does NOT cannibalize those branches (declined→not-auto, blocked→alreadyContact, replay→dedup, existing-contact key-update→unchanged). The reciprocal-send surface is reused unchanged (acceptAndReciprocate), so no sibling drift.
- **Destructive-action side-effects:** TC-04 asserts the inbox `deleteEntry` happens ONLY after a durable commit (what is removed vs preserved) — the one new "destructive" path. No new delete/cleanup elsewhere.
- **Invariant re-verification under new transitions:** the new transition is "pending → auto-accepted (no tap)". TC-06 asserts the FULL post-transition state: contact added + status accepted + reciprocal fired + NO dialog emission + notice emitted. TC-08 re-verifies the mutual invariant (exactly one row each, no loop) after the transition.

## Invariants (locked by tests)
- INV-1: a cold/just-online receiver still ends up MUTUAL (adds the scanner AND reciprocates) from its relay inbox, surviving the listener-subscribe race → **TC-04 (persist) + TC-14 (inbox→add+reciprocal) + TC-13 (device)**. NOT TC-08 — two synchronous `FakeP2PService` deliver to B's live listener and cannot reproduce the unbuffered-broadcast subscribe-race.
- INV-2: only v2-encrypted (recipient-bound) requests auto-add; v1 stays manual → TC-07.
- INV-3: auto-add never resurrects a declined peer and never adds a blocked peer → TC-09, TC-10.
- INV-4: exactly one contact row per side; reciprocal terminates (no loop — A issues ZERO reciprocal sends) → **TC-08 (with `A.reciprocalSendCount == 0` assertion)** + TC-14.
- INV-5: deferring the ack does not strand it — a live receiver confirms (incl. the auto-add happy path); a cold one times out → durable inbox → TC-02 (Go) + TC-03 (Dart confirm) + TC-06 (confirm on contactAutoAdded path) + TC-04/TC-14.
- INV-6: replay/dedup holds across BOTH same-process (volatile cache) AND restart (durable row) — no double auto-add / double reciprocal → **TC-12 (listener cache) + TC-15 (durable-row dedup after remount)**.
- INV-7: the offline one-scan case is eventually consistent — a QR contact (null ML-KEM) keeps re-sending on resume/periodic retry, and a re-send lands on a cold B → mutual once connectivity returns → **TC-16 (Shape A retry-eligibility + Shape B cold-B landing)**. (Mutual-scan-offline needs no network and is covered by the local-add path; no test needed — it's a pure local DB write.)
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Record `git status --short` (dirty-tree snapshot; shared new-orbit tree).
2. Add ALL RED tests (TC-01…TC-13 host/Go rows); run focused cmds; confirm RED for the documented reason (mutation-first rows: apply the named mutation to prove the lock).
3. Go: `node.go` `shouldDeferDirectAck` add `case "contact_request": return true` (`~:1631`); fix the stale comment `:1626-1629`; update `transport_label_test.go:499`. Verify `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./node/ ./bridge/` + `make lint`; revert `testdata/interop_vectors.json`.
4. **Extract `ContactRequestListener.processIncomingMessage(ChatMessage) -> Future<HandleMessageResult>`** (refactor): move the `_onMessage` body into the new PUBLIC method; `_onMessage` becomes a thin delegate. ALL receive logic (handle + dialog/auto-accept + confirm + notice + replay-cache add) lives here so the inbox arm (step 8) reuses it verbatim — this is the fix for the dominant-bug cold path (chat/intro already did this exact refactor: `main.dart:2039/2218`). Stop-if: signature can't stay `(ChatMessage)` because the inbox arm needs extra context → thread it explicitly, do not duplicate the logic.
5. Dart confirm: inside `processIncomingMessage`, after the handle returns, call `callP2PConfirmDirectMessage(bridge, message.confirmNonce, ok:true)` for EVERY returned result (incl. `contactAutoAdded` — the live happy path); thrown error → `ok:false`; null nonce → no call. The confirm must fire on the SAME code path as (and after) the auto-accept — do NOT early-`return` from the `contactAutoAdded` branch before the shared confirm. Stop-if: `ChatMessage` lacks a `confirmNonce` field → re-verify the router/model carries it before proceeding (do not hack a side channel).
6. Dart auto-add: in `handle_incoming_message_use_case.dart`, BEFORE step-10 (`:387`), add the v2 auto-add branch gated by: `version=='2'` AND no existing `declined` request row (load via `requestRepo.getRequest(peerId)`) AND `getContact(peerId)?.isBlocked != true` (defensive; step-8 `contactExists` is the primary block-catch) AND rate-limiter allows. On pass → store pending (audit) + return `HandleMessageResult.contactAutoAdded`; else fall through to `contactRequest`. Add `contactAutoAdded` to the enum (`:13-34`). Route ML-KEM via the existing `:325-353` guard (don't overwrite older).
7. Dart listener routing (inside `processIncomingMessage`): add a `contactAutoAdded` branch → `acceptAndReciprocateContactRequest(peerId)` + emit `CONTACT_AUTO_ADDED` notice (non-modal) + DO NOT `_requestController.add`; add `contactAutoAdded` to the replay-cache OR-list (`:198-202`). Respect `kE2ETestMode`.
8. Dart inbox durability: add `_replayRecoveredInboxContactRequest` callback that calls `contactRequestListener.processIncomingMessage(...)` + a `contact_request` arm in `_replayStagedInboxEntries` (persist/commit BEFORE `deleteEntry`), wired from `main.dart` (mirror chat/intro `main.dart:2039/2218` + `p2p_service_impl.dart:1414-1444`). **Terminal-result → committed (delete) mapping MUST include `contactAutoAdded` AND `contactRequest`** alongside `alreadyContact`/`duplicateRequest`/`invalidMessage`/`silentIntroRecovered`; ONLY a thrown error → retryable. (Omitting the two common new-request outcomes → every drained request re-replays → re-auto-add/re-reciprocate, violating INV-6.)
9. Rate-limiter: small in-memory util (per-peer + global window); inject into the auto-add decision (param on `handleIncomingMessage` or the listener — prefer the listener so `handleIncomingMessage` stays pure; decide during RED).
10. Rerun direct → preservation → named gates (below).

## Risks And Edge Cases
- **Go-only change regresses (2s timeout).** → TC-02 + TC-03 pin that the Dart confirm exists and fires; do not land step 3 without step 4.
- **Declined/blocked resurrection.** → TC-09/TC-10.
- **Spam/amplification (auto-add + auto-reciprocate any v2 peer).** → TC-11 rate-limit + v2-only (recipient-bound) gate; non-modal notice gives undo/block. Residual risk accepted per user decision (vs the stricter QR-nonce option) — recorded in Accepted Differences.
- **Confirm ok-mapping mis-set drops requests.** → TC-03 asserts ok=true on returned results (incl terminal rejects, which are correctly final) and ok=false only on a thrown error (so a real transient failure inboxes).
- **Narrow concurrent direct+inbox double-deliver (v1 → two dialogs).** Pre-existing relay double-delivery race; DB row stays single (upsert-by-peerId). Acknowledged, not a blocker; TC-12 covers the v2 msgId dedup.
- **Account-migration gate** may drop inbound before the listener → no confirm → 2s timeout → inbox; correct (side effect intentionally blocked).
- **Two like-named listener files** — edit only `lib/features/contact_request/application/contact_request_listener.dart`.

## Device/Relay Proof Profile
Requires the 2-phone rig for closure (TC-13). The rig is already provisioned this session (Pixel 6 + iPhone 11 + iPhone 13, same Wi-Fi; EC2 relay live with Redis durability `relay_backend_durable=1`).
Closure scenario: `/sims 1to1 --only N` (the new `contact_one_scan_mutual_d1`). Capture `[FLOW]` on the RECEIVER (idevicesyslog for iPhone 13 / `devicectl --console` for iPhone 11 / `adb logcat` for Pixel).
Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (peer-ID unchanged this deploy).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot first (shared new-orbit tree)
git status --short

# RED (before production edits) — must FAIL for the documented reason
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./node/ -run TestShouldDeferDirectAck -count=1   # TC-01 RED
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart --plain-name 'contactAutoAdded'   # TC-05 RED

# Go GREEN (after fix) — run under the pinned toolchain, then revert interop
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./node/ ./bridge/ -count=1    # expect: ok node, ok bridge
GOTOOLCHAIN=go1.25.0 make -C go-mknoon lint                             # expect: 0 issues
git checkout -- go-mknoon/testdata/interop_vectors.json

# Dart direct GREEN
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart
flutter test test/features/contact_request/application/contact_request_listener_test.dart
flutter test test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart
flutter test test/core/services/p2p_service_contact_request_inbox_replay_test.dart

# Preservation sentinels (must stay green)
./scripts/run_test_gates.sh 1to1            # expect: prior 1to1 count + new (record baseline first)
./scripts/run_test_gates.sh feed            # expect: unchanged pass count
./scripts/run_host_test_gates.sh core-host-all   # expect: unchanged + TC-04

# Named gate(s) for the touched subsystem
./scripts/run_test_gates.sh 1to1            # contact_request lives in the 1:1 family

# Simulator/device discovery + run (device-proof TC-13)
./scripts/check_reliability_simulation_discovery.sh   # contact_one_scan_mutual_d1 MUST list, exit 0
# /sims 1to1 --list → note --only N → /sims 1to1 --only N

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01/02/03/04/05/06/08/11/13/14 fail on HEAD before the fix (documented reasons above). **TC-14 (cold-B inbox mutual) also fails against a naive "mirror-intro arm that only calls `handleIncomingMessage`"** — it is RED until the public `processIncomingMessage` is wired into the inbox arm.
- Mutation-first RED (PASS on HEAD; RED via the named mutation): **TC-07, TC-09, TC-10, TC-12, TC-15, TC-16 Shape A** (retry-eligibility of a null-ML-KEM QR contact pre-exists; its RED is the "make ML-KEM non-null → excluded" mutation). **TC-16 Shape B** (re-sent request landing on a cold B) is Expected-RED on HEAD. (TC-09 moved here from Expected-RED per audit finding #3 — on pristine HEAD a declined peer already falls to `contactRequest`/dialog with no add, exactly TC-09's assertion, so it would surface a false "unexpectedly green" if run as Expected-RED.)
- Pre-existing dirty: P4.0 device-campaign edits / other live-session WIP in the tree — record in the dirty snapshot, do NOT revert.
- Environment blocker (NOT product): TC-13 needs the 2-phone rig + unlocked phones + iOS Local Network granted; a missing/locked device is an env blocker, not a product fail.
- Scope drift (BLOCKING): any failure outside the Scope Guard (e.g. a chat/reaction deferred-ack regression, or a feed gate drop).

## Done Criteria
- [ ] RED added first, failed for the expected reason (mutation-first rows proven via their mutation).
- [ ] Each fix mutation-verified (named revert re-reds).
- [ ] Go ./node/ + ./bridge/ + lint green (go1.25.0); interop reverted.
- [ ] Dart direct GREEN + 1to1/feed/core-host-all preservation green.
- [ ] No DB migration (uses existing `contacts`/`contact_requests` columns) — N/A justified.
- [ ] TC-13 device-proof green on ≥1 OS pair (closure gate).
- [ ] Every new test's harness-registration done (TC-08 arrays; TC-13 classify_path + `--scenario`) and verified in a gate/`/sims` run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do NOT add a method to `ContactRepository` or `P2PService` (use existing `getContact().isBlocked`; would trigger the 28-/33-fake cascade).
- Do NOT edit `lib/core/services/contact_request_listener.dart` (hollow stub) or `lib/features/qr_code/application/handle_scanned_qr_use_case.dart` (orphaned).
- Do NOT auto-add v1-plaintext requests (no recipient binding).
- Do NOT change `EnableDeferredDirectAck` default or rename the `confirmNonce`/`message:confirm` wire keys.
- Do NOT flip any FDC prod transport flag (owned by Phase-4 device campaign).
- Do NOT land the Go deferred-ack (step 3) without the Dart confirm (step 5).
- Do NOT wire a "mirror-intro" inbox arm that calls `handleIncomingMessage` directly — it commits-and-deletes but never auto-adds/reciprocates (cold B stays non-mutual). The arm MUST call the extracted public `ContactRequestListener.processIncomingMessage` (the dominant-bug trap, audit finding #1).

## Accepted Differences / Intentionally Out Of Scope
- QR-nonce co-presence binding (stricter anti-spam) — user chose "auto-add v2"; this is a stronger follow-on if spam emerges.
- `send_contact_request_use_case.dart` "always-inbox on success" (leg b) — redundant given deferred-ack; revisit only if device evidence shows a gap.
- Persistent (cross-restart) rate-limit — in-memory suffices; persistence would need a DB migration.
- A dedicated `contact_request_outbox` table (mirroring `introduction_outbox`, migration 047) — NOT needed: a QR contact's `mlKemPublicKey==null` row already IS the durable outbound queue, drained by `retryIncompleteKeyExchanges` on resume/periodic. TC-16 locks that behavior; a second outbox would duplicate it.
- Airplane-mode device-proof variant of TC-13 (scan offline → enable network → mutual) — nice-to-have closure; the host TC-16 + TC-04/14 cover the mechanism. Deferred to the device campaign if the host evidence is judged insufficient.

## Dependency Impact
- The FDC Phase-4 CV-08 device campaign depends on this: the two-phone contact pairing must work for the LAN-direct proof (this session hit exactly this bug). Once landed, CV-08 setup no longer needs the mutual-scan workaround.

## Reviewer Findings
Audit pass 2026-06-28 (post-draft) — 9 findings, ALL accepted and folded in:
- **CRITICAL (source-verified):** the cold-B inbox-replay path (the plan's own dominant bug) would NOT become mutual — auto-add/reciprocal/confirm live in the listener's PRIVATE void `_onMessage:172`; the inbox arm needs a PUBLIC method (chat/intro expose `processIncomingMessage`, reused at `main.dart:2039/2218`; CR had none). → Scope now extracts a public `ContactRequestListener.processIncomingMessage`; NEW **TC-14** asserts add+reciprocal from the inbox path before delete; step 8 routes the arm through it.
- **MED:** step-8 terminal mapping omitted `contactAutoAdded`/`contactRequest` → re-replay loop. → step 8 mapping fixed.
- **HIGH:** TC-12 mutation vacuous (use-case test can't see the listener cache). → re-tiered to the listener (`contact_request_listener_test.dart`).
- **HIGH:** TC-10 matrix cell dropped the compound mutation (block guard is dead vs step-8). → cell fixed to the compound mutation + redundancy noted.
- **MED:** TC-09 is mutation-first, not Expected-RED. → re-bucketed.
- **MED:** TC-04 asserted a flow event, not a real persist. → bound to an `addRequest/addContact` write on a recording fake before `deleteEntry`.
- **MED:** INV-1/INV-4 over-credited to fake-net TC-08. → INV-1 remapped to TC-04/TC-14/TC-13; TC-08 gains `A.reciprocalSendCount==0` for INV-4.
- **MED:** confirm not asserted on the `contactAutoAdded` happy path (early-return = 2s timeout where it matters most). → TC-06 asserts `acceptAndReciprocate` THEN `confirm(ok:true)`, in order, once.
- **MED:** no restart/fresh-mount dedup test (volatile `_replayCache`). → NEW **TC-15** locks durable-row dedup after remount.
Result: 13 → **15 test cases**; matrix + invariants + step-by-step + known-failure buckets updated accordingly.

Review pass 2026-06-28b ("offline / no-internet"): corrected a WRONG draft claim (a QR contact is `mlKemPublicKey==null`, so it IS eligible for the existing resume/periodic `retryIncompleteKeyExchanges` — the draft said the opposite). Added the **Offline / No-Relay Handling** section (3 sub-cases) + **TC-16** + INV-7. Net: **16 test cases**. Key conclusion: the offline one-scan case is eventually-consistent via the existing null-ML-KEM-row-as-outbox retry, but ONLY once this plan's deferred-ack/staged-replay make the re-send land on a cold B — so no new outbox/migration is needed.

## Arbiter Decision
(pending)

## Final Execution Verdict
IMPLEMENTED — host-green (2026-06-28). All 16 TC rows landed RED-first and mutation-verified (Go TC-01/02 RED-first; TC-03/06 via confirm-removal; TC-11 limiter; TC-12 replay-cache — TC-12 was caught VACUOUS first, fixed to use a working request repo so the replay cache is the sole dedup; TC-07 v2-gate; TC-09 declined-guard; TC-10+TC-15 via a step-8-reorder mutation; TC-04/14/16-B via arm-disable). Go ./node/ ./bridge/ + lint green (go1.25.0); CR suite +100 green; **1to1 +1387 ALL PASS**; core-host-all PASS; analyze 0-new; diff-check clean; no DB migration. A 5-agent read-only review confirmed the deferred-ack 2s-regression is eliminated (skeptic walked all 6 result paths — every confirmNonce path fires exactly one confirm) and found one BLOCKER (auto-add silently lost the request if the local accept hit a DB error — committed+deleted with no contact) → FIXED with a graceful dialog fallback (the request is already durably pending) + a new lock test; plus a MED late-var-capture nit → made explicit.

OPEN (env-gated, NOT a product fail): **TC-13** device-proof on the 2-phone rig. Scenario `contact_one_scan_mutual_d1` is registered + discoverable (gate exit 0); the run is the manual `/sims 1to1 --only N` (deferred — needs both phones unlocked + iOS Local Network granted). Per the project pattern (FDC plans), the change is host-green and NOT committed.

DEVIATION from the draft: TC-13 follows the established `manual-two-phone` convention (scenario-only, like fdc11/fdc15) — NO `integration_test/contact_one_scan_mutual_proof_test.dart` was created, since the sibling manual scenarios have none and an unregistered integration_test file would trip the FAIL-CLOSED discovery gate.
