# Libp2p Introduction Test Matrix with Coverage Rules

## Scope

This file reviews the Introduction feature, keeps the strong journeys already visible in your current intro suite, adds the meaningful missing ones, and maps each journey to the right automation layers without forcing all five layers on every test.

The goal is not just feature completion. The goal is **convergence**: if A introduces B and C, all three nodes should eventually agree on the same intro state, contact state, notification state, and repair behavior even under retries, duplicates, offline delivery, replay, and restart.

## Actors

- **A** = introducer (already has B and C as contacts)
- **B** = recipient
- **C** = introduced party
- **X** = unauthorized / non-party caller

## Priority guide

- **P0** = release-blocking; core handshake correctness, state convergence, permissions, and data integrity
- **P1** = important; should be covered before broad rollout
- **P2** = optional or polish-heavy; cover before scale-out or if the feature is user-visible in production

## Minimum introduction rules and invariants

These are the baseline feature rules this matrix assumes:

- A can introduce B and C only when A already has both as contacts.
- B and C are not already contacts for the normal pending path; if they already are contacts, the intro must surface as **alreadyConnected** instead of producing a second relationship.
- Both B and C must accept before contacts are created.
- A single **pass** from either side makes the overall intro terminal as **passed**.
- An intro older than 30 days becomes **expired**.
- Contacts between B and C are created locally only after **mutualAccepted**.
- Blocking suppresses new `send` offers from blocked introducers, but must not break accept/pass completion for an already-started intro.
- Pending badges count only true pending intros; `alreadyConnected`, `passed`, and `expired` must not inflate the badge.
- Outbox + inbox/store-and-forward + startup reconciliation must eventually converge or leave an explicit retryable state with a reason.

## Current repo execution note (2026-04-09)

Use this note when turning the matrix into repo-local work:

- Strong current coverage already exists for send/accept/pass core behavior, already-connected handling, banner gating, deferred-response replay, mutual-acceptance contact creation, sender-local crash-window durability, offline inbox convergence in in-memory multi-node tests, intro notification routing, Orbit intro sliver and banner variants, FriendPickerWired full flow, SentConfirmationWired pass-through, push title/body content, and targeted three-simulator proof for partial fan-out, sender-side repair, partition-heal convergence, offline-relay-to-first-chat recovery, and symmetric pass-fallback drain.
- Thin or missing non-row-specific coverage still exists around migrations 019/022/023/025/047, DB helper-specific SQL correctness, isolated already-connected delivery-tier fast-path proof, some batch-progress failure edges, intro flow-event inventory, end-to-end push trigger delivery, and transport proof that remains outside this matrix's row-owned closure bar.
- Execution rule for this matrix: do **not** let in-memory integration tests replace fake-network or 3-simulator coverage on transport-sensitive rows.

## Coverage policy used in this matrix

### Coverage legend

- **Required** = should exist for this journey before you treat the feature as production-ready.
- **Recommended** = high-value coverage, but not mandatory for every release gate.
- **N/A** = do not force this layer for this journey.

### Rules

**Unit**  
Use for logic-heavy pieces:
- role checks
- dedupe
- replay protection
- epoch/key rotation
- notification suppression after removal
- unread counter logic
- state transitions such as `removed -> rejoined`

**Integration**  
Use for most journeys:
- add/remove member
- promote admin
- re-invite
- send/receive
- notification behavior
- metadata sync

**Smoke**  
Keep this small and release-blocking:
- create group
- online fan-out
- add member
- remove member
- removed member blocked
- re-invite works
- admin promotion works

**Fake Network**  
Use where the network behavior is the main risk:
- retries
- duplicates
- offline recipient
- reconnect
- relay/store-and-forward
- partition healing
- removal boundary
- queued delivery after removal
- concurrent admin changes

**3-party E2E (3 simulators)**  
Use for user-visible A/B/C flows:
- A sends and B/C receive
- A removes C
- C stops receiving/sending
- A re-invites C
- B gets promoted to admin
- notification deep-link behavior
- member list and role badges sync across devices

### Matrix interpretation

- **Integration** is Required for most rows because intro reliability is emergent across local state, crypto, persistence, transport, and UI.
- Rows that are mostly UI-facing should also have widget coverage in practice, even though widget tests are not a dedicated column in this matrix.
- Some security and repair rows only need **Recommended** 3-party E2E because they usually also need a fake transport harness or debug observability to assert correctly.

## Missing journeys added in this revision

Compared with the current intro inventory, this revision explicitly adds or sharpens the journeys most likely to explain “sometimes works, sometimes not”:

- non-party caller guard on `acceptIntroduction` / `passIntroduction`
- delivery-tier isolation: local/direct race, relay probe, partial fan-out
- multi-row app-resume retry and prior inbox cleanup
- sender crash after remote delivery but before local intro persistence
- split-brain mutual acceptance healing after reconnect/restart
- replay / tamper / key-mismatch hardening
- active Orbit intro sliver copy and pending-count banner coverage
- FriendPickerWired and SentConfirmationWired full flows
- push notification title/body validation
- true 3-simulator offline / reconnect / restart proof

## Core Introduction Lifecycle

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| IL-001 | Banner shown only when all six gates pass | 1:1 conversation exists with contact B; A has at least one other eligible contact. | 1. Evaluate banner gate with each prerequisite satisfied. 2. Flip each gate off in separate runs. | Banner appears only when blocked=false, archived=false, banner not dismissed, intros not yet sent, messageCount < 3, and at least one other eligible contact exists. | P0 | Required | Required | N/A | N/A | N/A | Inventory: Covered by `check_intro_banner_test.dart`, `check_intro_banner_extended_test.dart`, and regression case 10. |
| IL-002 | Banner dismissal persists, but overflow re-entry still works | A is eligible to introduce B to others. | 1. Dismiss the banner. 2. Re-open the conversation later. 3. Use overflow/menu entry to start an intro. | Banner stays dismissed, but A can still re-enter the intro flow intentionally from overflow/menu. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered by `introduction_smoke_test.dart`, `intro_wiring_smoke_test.dart`, and `conversation_overflow_intro_test.dart`. |
| IL-003 | Friend picker filters recipient / self / blocked / archived contacts while keeping re-introducible pairs selectable | A is in a conversation with B and has additional contacts, including blocked or archived ones. | 1. Open the picker. 2. Inspect the list. 3. Repeat after a previous intro exists for the same pair. | Recipient, self, blocked, and archived entries are not selectable; eligible previous same-pair intros can still be re-sent. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `friend_picker_wired_test.dart` recipient/self/blocked/archived exclusion plus same-pair reintroduction coverage, `friend_picker_test.dart` picker UI-state coverage, and the rerun Intro / Reintroduction Gate on 2026-04-08. |
| IL-004 | Single introduction send creates one shared introId, two outbound envelopes, and one local row | A knows B and C and both are valid targets. | 1. A sends an intro from B's conversation to C. 2. Inspect outbound payloads and A's local intro repository. | Both outbound `send` payloads share the same `introductionId`; A persists one intro row for the pair. | P0 | Recommended | Required | Required | Recommended | Required | Inventory: Covered by `send_introduction_test.dart` and `introduction_multi_node_test.dart`. |
| IL-005 | Batch send keeps a concurrency cap of 10, stable ordering, and truthful progress | A selects more than 10 friends to introduce to a recipient. | 1. Send a large batch. 2. Observe active work count, result order, and progress callback timing. | No more than 10 intro chains run at once; final results stay in input order; progress only advances when each chain settles. | P1 | Required | Required | N/A | Recommended | N/A | Inventory: Covered by `send_introduction_test.dart`. |
| IL-006 | v2 is preferred when an ML-KEM key exists; v1 fallback is used when the key is absent or encrypt fails | Target contact may or may not have an ML-KEM public key; bridge encryption may fail. | 1. Send to targets with and without ML-KEM keys. 2. Force encryption failure in a separate run. | Envelope selection follows product rules: v2 when possible, v1 only as fallback. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `send_introduction_test.dart`, `accept_introduction_test.dart`, `pass_introduction_test.dart`, and regression case 11. |
| IL-007 | Online receipt creates a pending intro row, system message, and local notification | B and C are online and listening. | 1. A sends an intro. 2. Inspect B and C receive-side state. | Each side gets a pending intro row, correct system copy, and a local intro notification. | P0 | Recommended | Required | Required | N/A | Required | Inventory: Covered by `introduction_listener_test.dart`, `introduction_multi_node_test.dart`, and `introduction_smoke_test.dart`. |
| IL-008 | Offline recipient later receives the intro via inbox / store-and-forward | C is offline while B is online. | 1. A sends intro to B and C. 2. Bring C back online and drain inbox. | B receives immediately; C later materializes the same intro once, without duplicate rows. | P0 | Recommended | Required | N/A | Required | Required | Inventory: Covered by `introduction_multi_node_test.dart` offline relay flow. |
| IL-009 | Blocked introducer `send` is rejected without intro row, UI, or notification | B or C has blocked A before receipt. | 1. A sends a new intro to the blocking peer. 2. Observe listener outcome and local state. | The `send` is acknowledged as blocked/rejected, but no intro row, system message, or notification is created. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `introduction_listener_test.dart`. |
| IL-010 | Already-connected intro is visible but non-actionable and does not inflate the pending badge | B and C are already contacts when A sends the intro. | 1. A sends the intro anyway. 2. Observe load/pending-count/UI state. | Intro is surfaced as `alreadyConnected`, shows no accept/pass actions, and does not increment pending counts. | P0 | Required | Required | Required | N/A | Required | Inventory: Covered by `handle_incoming_introduction_test.dart` already-connected visibility and pending-badge exclusions, `intro_row_test.dart` non-actionable `Already connected` UI coverage, `introduction_multi_node_test.dart` existing-contact convergence, and the rerun Intro / Reintroduction Gate on 2026-04-08. |
| IL-011 | Duplicate or older same-pair `send` is ignored; newer same-pair `send` replaces stale row | A has already introduced the same pair before. | 1. Deliver same-pair intros with older, equal, and newer timestamps. 2. Observe stored rows. | Older or equal messages are ignored; newer same-pair intros replace stale rows without duplicating the pair. | P0 | Required | Required | N/A | Recommended | Recommended | Inventory: Covered by `handle_incoming_introduction_test.dart` and `introduction_smoke_test.dart`. |
| IL-012 | Introducer-side row reflects later accept/pass updates from both parties | A has already sent a valid intro to B and C. | 1. B accepts or passes. 2. C responds later. 3. Observe A's local row after each update. | A's persisted intro row tracks both remote responses and converges to the same overall terminal state seen on B and C. | P0 | Recommended | Required | N/A | N/A | Required | Inventory: Covered by `introduction_multi_node_test.dart`; the inventory note explicitly says the seam exists even if the prose summary undercounts it. |
| IL-013 | Intro expires after 30 days, and a fresh re-introduction after expiry starts a new valid journey | An old intro is older than 30 days. | 1. Age the intro beyond 30 days. 2. Verify it is no longer pending. 3. Re-introduce the same pair. | Old row is terminal `expired`; a new re-introduction creates a new valid pending flow instead of reviving stale state. | P1 | Required | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by the expired-refresh regressions in `send_introduction_test.dart` and `introduction_smoke_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro`. |

## Responses and Mutual Connection

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RM-001 | One-sided accept shows waiting / partial state and creates no contact | A sent a valid intro; only one party has responded. | 1. B accepts while C is still pending. 2. Inspect B, C, and A. | B shows waiting-for-other-party state; overall stays pending; no B/C contact is created yet. | P0 | Required | Required | N/A | N/A | Required | Inventory: Covered by `accept_introduction_test.dart`, `mutual_acceptance_test.dart`, `intro_row_test.dart`, and smoke coverage. |
| RM-002 | Accept order is irrelevant | A sent a valid intro and both parties will accept. | 1. Run B-then-C. 2. Run C-then-B. | Both orders converge to the same final statuses, contacts, and user-visible copy. | P0 | Required | Required | N/A | Recommended | Required | Inventory: Covered by `mutual_acceptance_test.dart` and `introduction_multi_node_test.dart`. |
| RM-003 | A pass from either side yields terminal `passed` and no contact | A valid intro exists. | 1. B passes in one run. 2. C passes in another run. | Overall becomes `passed`, remains terminal, and no contact is created between B and C. | P0 | Required | Required | Required | N/A | Required | Inventory: Covered by `pass_introduction_test.dart`, `mutual_acceptance_test.dart`, and `introduction_smoke_test.dart`. |
| RM-004 | One side accepts and the other later passes; overall remains `passed` | A valid intro exists and one side already accepted. | 1. B accepts. 2. C passes later. | Overall resolves to `passed`; no contact is created and the prior accept does not force mutual acceptance. | P0 | Required | Required | N/A | N/A | Required | Inventory: Covered by `mutual_acceptance_test.dart` and `introduction_multi_node_test.dart`. |
| RM-005 | Accept after a terminal pass never reopens the intro | The intro already reached `passed`. | 1. Force a later accept from the opposite side. 2. Re-load intro state. | The intro remains `passed`; no reopening, no contact creation, and no terminal-state regression occur. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `mutual_acceptance_test.dart` (`accept after pass still results in passed`). |
| RM-006 | Accept/pass is sent to both the introducer and the stranger, using intro-carried keys first and contact fallback second | B or C is responding to a valid intro. | 1. Accept or pass from B. 2. Inspect delivery to A and the other party. 3. Repeat with missing stranger ML-KEM key. | Both recipients get the response; stranger-target encryption prefers intro-carried keys and falls back safely when needed. | P0 | Required | Required | N/A | Recommended | Required | Inventory: Covered by `accept_introduction_test.dart` and `pass_introduction_test.dart` both-recipient delivery, intro-carried stranger-key, and stranger contact-fallback ML-KEM coverage, plus the rerun Intro / Reintroduction Gate on 2026-04-08. |
| RM-007 | Duplicate accept/pass deliveries are idempotent | A response envelope can be delivered more than once. | 1. Deliver the same accept twice. 2. Repeat for pass. | Only one logical state transition is applied; no duplicate contacts, rows, or notifications appear. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered by `introduction_regression_test.dart` duplicate accept and duplicate pass idempotency regressions, plus the rerun Intro / Reintroduction Gate on 2026-04-08. |
| RM-008 | Unknown responderId is rejected with no mutation | An intro exists, but an inbound response names a peer who is neither recipient nor introduced. | 1. Deliver an accept or pass with an unknown responderId. | The message is rejected; intro statuses and contacts remain unchanged. | P0 | Required | Required | N/A | N/A | N/A | Inventory: Covered by regression case 2. |
| RM-009 | Non-party caller cannot invoke accept/pass on an intro they do not belong to | X is neither recipient nor introduced for the intro. | 1. Call `acceptIntroduction` as X. 2. Call `passIntroduction` as X. | Use case rejects or no-ops safely; no status drift occurs and no outbound messages are sent. | P0 | Required | Recommended | N/A | N/A | N/A | Inventory: Covered by `accept_introduction_test.dart` and `pass_introduction_test.dart` non-party caller no-mutation regressions, the explicit non-party guards in the response use cases, and the rerun Intro / Reintroduction Gate on 2026-04-08. |
| RM-010 | Accept/pass from a now-blocked stranger still completes the handshake path | B or C blocks the other party after the intro exists but before final response processing. | 1. Establish intro. 2. Add a block. 3. Deliver accept/pass. | Handshake completion still works for accept/pass messages; blocking only suppresses new `send` offers. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `introduction_listener_test.dart` and regression cases 14a/14b. |
| RM-011 | The second accept creates exactly one contact on each side with correct keys and introducedBy metadata | A valid intro exists and one side has already accepted. | 1. Deliver the second accept. 2. Inspect contacts on B and C. | B and C each get exactly one new contact with correct peerId, keys, and introducer metadata. | P0 | Required | Required | Required | N/A | Required | Inventory: Covered by `create_connection_on_mutual_acceptance_test.dart`, `introduction_multi_node_test.dart`, and regression cases 7a/7b. |
| RM-012 | Introducer converges to `mutualAccepted` without duplicate B/C contacts | A already knows both parties. | 1. Drive both accepts. 2. Inspect A's intro row and contact list. | A's intro row reaches `mutualAccepted`, but A does not create duplicate contacts for B or C. | P0 | Recommended | Required | N/A | N/A | Required | Inventory: Covered by `introduction_multi_node_test.dart` introducer `mutualAccepted` / no-duplicate-contact regression, the existing introducer-local persistence proof in the same suite, and the rerun Intro / Reintroduction Gate on 2026-04-08. |
| RM-013 | Mutual acceptance creates system message and new-connection notification; avatar retry failure does not roll back the contact | B and C are about to reach mutual acceptance. | 1. Complete mutual acceptance. 2. Force avatar download failure in a separate run. | Contact creation is durable; system message and local connect notification appear; avatar failure never removes the contact. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by `create_connection_on_mutual_acceptance_test.dart` system-message and avatar no-rollback regressions, `introduction_listener_test.dart` local new-connection notification coverage, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| RM-014 | First encrypted chat works immediately after mutual acceptance | B and C become contacts through the intro. | 1. Complete mutual acceptance. 2. Send first direct encrypted message between B and C. | First chat succeeds without a separate QR scan or extra key exchange. | P0 | N/A | Required | Required | Recommended | Required | Inventory: Covered by `introduction_multi_node_test.dart` offline-relay-to-first-chat scenario. |
| RM-015 | `resolveUnknownInboxSender` repairs a missing contact when intro state proves the contact should exist | A mutually accepted intro exists, but one side lacks the local contact row. | 1. Remove or miss the contact row locally. 2. Deliver an inbox message from the unknown new contact. 3. Run resolver. | Resolver returns `contactRecovered` or `retryable` according to intro truth, and the missing contact can be recreated without user intervention. | P1 | Required | Required | N/A | Recommended | Recommended | Inventory: Covered by `resolve_unknown_inbox_sender_use_case_test.dart`. |
| RM-016 | `expireOldIntroductions` heals stale rows to mutualAccepted/passed/expired and reruns missed side effects | Stored overall status is stale relative to party statuses or age. | 1. Seed stale rows. 2. Run startup reconciliation. 3. Inspect rows and contacts. | Rows are healed to derived truth; missed mutual-accept side effects rerun when appropriate; alreadyConnected rows stay untouched. | P1 | Required | Required | N/A | N/A | N/A | Inventory: Covered on 2026-04-09 by the expanded `expire_old_introductions_use_case_test.dart` matrix for mutualAccepted/passed/expired healing, plus a green rerun of `./scripts/run_test_gates.sh intro`. |

## Delivery, Ordering, and Recovery

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| DR-001 | Acked direct send clears the staged outbox row | Direct live transport is available and the receiver acks. | 1. Send an intro over the direct path. 2. Observe outbox after ack. | Outbox row is removed once delivery is confirmed. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered by `introduction_outbound_delivery_test.dart`. |
| DR-002 | Unacked live send stays retryable, and resume retrier replays via inbox-only semantics | Direct send returns without a final ack. | 1. Send an intro with an unacked live path. 2. Trigger retry later. | Outbox row remains retryable; retry flow uses inbox-only semantics and does not re-run the full cascade. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered by `introduction_outbound_delivery_test.dart` unacked retry-state plus `handleAppResumed` inbox-only replay coverage, and the rerun Intro / Reintroduction Gate on 2026-04-08. |
| DR-003 | Local/direct race converges cleanly with no duplicate intro rows or duplicate delivery side effects | Target can be reachable by local LAN and direct dial near-simultaneously. | 1. Make both race arms viable. 2. Release them with timing skew. | Only one logical intro is stored and processed; race winners do not duplicate rows or notifications. | P1 | Recommended | Recommended | N/A | Required | Recommended | Inventory: Covered on 2026-04-09 by the forced local/direct race regression in `introduction_smoke_test.dart`, the duplicate-send listener dedupe regression in `introduction_listener_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| DR-004 | Relay-probe fallback converges cleanly after direct paths fail | Direct/local paths fail but relay reservation is available. | 1. Force direct failure. 2. Allow relay probe and retry path. | Intro still converges using relay-assisted delivery without duplicate state transitions. | P1 | N/A | Recommended | N/A | Required | Recommended | Inventory: Covered on 2026-04-09 by the isolated relay-probe fallback regression in `introduction_outbound_delivery_test.dart` and a green rerun of `./scripts/run_test_gates.sh intro`. |
| DR-005 | Partial fan-out is safe: B receives now, C later, and the pair still converges | B is online; C is temporarily unreachable. | 1. A sends intro. 2. B responds. 3. C reconnects later and completes. | Partial delivery does not poison the intro; late delivery still converges correctly. | P0 | Recommended | Required | N/A | Required | Required | Inventory: Covered by the delayed same-intro recovery regression in `introduction_multi_node_test.dart`, `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`, `./scripts/run_test_gates.sh intro`, and `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`. |
| DR-006 | Responses arriving before the `send` row are durably staged and replayed correctly | Accept or pass can arrive before the intro `send`. | 1. Deliver accept-before-send. 2. Deliver pass-before-send. 3. Deliver both accepts before send in another run. | Pending responses are staged, replayed when the `send` arrives, and still produce the correct final status and contact side effects. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered by `handle_incoming_introduction_test.dart`, `introduction_listener_test.dart`, and `introduction_multi_node_test.dart`. |
| DR-007 | Duplicate network deliveries and stale queued envelopes never reopen a terminal intro | A terminal intro exists and older queued traffic still drains later. | 1. Deliver stale queued `send` / `accept` / `pass` after terminal state. 2. Repeat with duplicates. | Terminal rows stay terminal; no reopen, no duplicate contact, and no duplicate system message occur. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered by `handle_incoming_introduction_test.dart` duplicate/stale terminal-send regressions, `mutual_acceptance_test.dart` `accept after pass still results in passed`, and `./scripts/run_test_gates.sh intro`. |
| DR-008 | App resume processes multiple stalled/failed rows and cleans prior delivered+inbox rows | Several outbox rows are retryable at resume time. | 1. Seed failed, stalled, and delivered+inbox rows. 2. Resume the app. 3. Run retry pass. | Failed/stalled rows are retried; delivered+inbox rows are cleaned; final retry count is accurate. | P1 | Required | Required | N/A | Required | Recommended | Inventory: Covered on 2026-04-09 by the multi-row retry cleanup regression in `introduction_outbound_delivery_test.dart`, the existing `handleAppResumed` intro-retry ordering proof, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| DR-009 | Sender crash after remote delivery but before local intro persistence heals on restart | Remote recipient already got the intro, but sender dies before saving local state. | 1. Deliver remotely. 2. Crash A before local save. 3. Restart and reconcile. | System heals to a consistent A/B/C view without permanent split-brain or duplicate intro rows. | P0 | N/A | Recommended | N/A | Required | Required | Inventory: Covered by the local-first sender persistence change in `send_introduction_use_case.dart`, the `send_introduction_test.dart` crash-window regression `persists the sender local intro row before a later delivery-stage crash`, `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh`, `./scripts/run_test_gates.sh intro`, and `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`. |
| DR-010 | Partition healing after divergent delivery or divergent accepts converges across A/B/C | Network partition causes different nodes to observe different subsets of intro traffic. | 1. Partition nodes. 2. Deliver different subsets of messages. 3. Heal the partition. | All nodes converge to one final truth once connectivity returns. | P0 | N/A | Recommended | N/A | Required | Required | Inventory: Covered by `introduction_multi_node_test.dart` partition-heal convergence, `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh`, and `./scripts/run_test_gates.sh intro` on 2026-04-09. |
| DR-011 | Offline relay intro delivery converges to mutual acceptance and first encrypted chat | At least one target is offline long enough to require inbox store-and-forward. | 1. A sends intro while C is offline. 2. C later drains inbox. 3. Complete both accepts. 4. Send first B↔C chat. | Offline delivery still reaches mutual acceptance; first chat works afterward. | P0 | Recommended | Required | Required | Required | Required | Inventory: Covered by `introduction_multi_node_test.dart` offline-relay-to-first-chat regression, `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh`, and `./scripts/run_test_gates.sh intro` on 2026-04-09. |
| DR-012 | Accept/pass notifications fall back to inbox while peers are unreachable and still converge after drain | Response targets are temporarily unreachable when B or C responds. | 1. Accept or pass while A or the stranger cannot be reached live. 2. Drain inbox later. | Response messages reach all intended recipients eventually; final status converges without duplicate effects. | P0 | Recommended | Required | N/A | Required | Required | Inventory: Covered by the `introduction_multi_node_test.dart` accept-fallback and pass-fallback inbox regressions, `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh`, and `./scripts/run_test_gates.sh intro` on 2026-04-09. |
| DR-013 | Re-introducing the same pair repairs a missed side and ignores stale older delivery | One side missed or failed to process an earlier intro. | 1. Re-send the same pair. 2. Also deliver a stale older intro later. | Fresh re-introduction repairs the missing side; stale older delivery is ignored. | P0 | Required | Required | Required | Required | Required | Inventory: Covered by `introduction_multi_node_test.dart` and `introduction_smoke_test.dart`. |
| DR-014 | Split-brain mutual acceptance heals after restart/reconnect | One side shows Connected while the other still shows Waiting due to timing skew. | 1. Reproduce the skew. 2. Restart or reconnect nodes. 3. Reconcile. | Nodes heal to the same final intro/contact truth without manual deletion. | P0 | N/A | Recommended | N/A | Required | Required | Inventory: Covered by `introduction_multi_node_test.dart` split-brain recovery regression, `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh`, and `./scripts/run_test_gates.sh intro` on 2026-04-09. |
| DR-015 | Multiple simultaneous intros stay isolated | A or several introducers create multiple intro chains concurrently. | 1. Run concurrent intros across different pairs. 2. Accept/pass some but not others. | One intro chain cannot mutate the status or contact state of another chain. | P1 | Required | Required | N/A | Recommended | Recommended | Inventory: Covered by `introduction_multi_node_test.dart` concurrent-chain isolation regression and `./scripts/run_test_gates.sh intro` on 2026-04-09. |
| DR-016 | Same pair with a different introducer reopens as alreadyConnected without duplicate contacts | B and C are already connected from a previous intro, and another introducer tries again. | 1. Let D introduce B and C after they are already connected. 2. Observe resulting intro state. | New row surfaces as `alreadyConnected`; no duplicate B/C contacts are created. | P1 | Required | Required | N/A | N/A | Required | Inventory: Covered by `introduction_multi_node_test.dart`. |

## Security, Correctness, and Convergence

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SC-001 | Replay of the same envelope / messageId / introductionId never duplicates rows, contacts, system messages, or notifications | A previously valid intro envelope can be replayed later. | 1. Replay same `send`. 2. Replay same `accept` after success. 3. Replay after terminal states. | Application remains idempotent at row, contact, system-message, and notification layers. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered on 2026-04-09 by the duplicate-send and duplicate-accept listener regressions in `introduction_listener_test.dart`, the late-delivery replay regression in `introduction_multi_node_test.dart`, the blocked duplicate-accept idempotency regression in `introduction_regression_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| SC-002 | Tampered ciphertext or wrong secret key is rejected with no state mutation | A v2 intro envelope is corrupted or decrypted with the wrong secret. | 1. Deliver malformed or tampered v2 payloads. 2. Repeat with wrong secret key. | Listener rejects the payload; no intro row, contact, badge, or notification is produced. | P0 | Required | Required | N/A | Required | N/A | Inventory: Covered on 2026-04-09 by the wrong-key and tampered-v2 listener regressions in `introduction_listener_test.dart` and a green rerun of `./scripts/run_test_gates.sh intro`. |
| SC-003 | ML-KEM key mismatch between intro record and current contact state is escalated or rejected, not silently accepted | Intro-carried stranger key disagrees with current contact truth. | 1. Seed a mismatch. 2. Try to send or process a response across that mismatch. | System surfaces a safe failure or repair path; it does not silently create the wrong trust edge. | P0 | Required | Required | N/A | N/A | N/A | Inventory: Covered on 2026-04-09 by the accept/pass mismatch regressions in `accept_introduction_test.dart` and `pass_introduction_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro`. |
| SC-004 | `ensureEnvelopeMessageId` patches missing `messageId` and still accepts legacy `id` envelopes | Outbound or older envelopes may be malformed or legacy-shaped. | 1. Build envelopes missing `messageId`. 2. Build envelopes with legacy `id`. | Outgoing envelope normalization is stable and dedupe-compatible. | P1 | Required | Recommended | N/A | N/A | N/A | Inventory: Covered on 2026-04-09 by the payload-helper regressions in `introduction_payload_test.dart`, including the new missing-`messageId` plus legacy-`id` normalization case, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| SC-005 | Blocked-sender rule applies only to `send`; accept/pass always pass through | One peer blocks another during the intro lifecycle. | 1. Deliver blocked `send`. 2. Deliver blocked accept/pass. | Blocked `send` is suppressed; blocked accept/pass still complete handshake semantics. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `introduction_listener_test.dart` and regression cases 14a/14b. |
| SC-006 | Key direction awareness remains correct when creating contacts | Mutual acceptance is about to create B↔C contacts. | 1. Complete mutual acceptance from recipient side. 2. Repeat from introduced side. | Recipient gets introduced party's keys; introduced party gets recipient's keys. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `create_connection_on_mutual_acceptance_test.dart` and regression cases 7a/7b. |
| SC-007 | `alreadyConnected` is terminal and visible, but not counted as pending | The pair is already connected when intro arrives. | 1. Receive already-connected intro. 2. Load pending count and UI rows. | `alreadyConnected` remains visible for context but never behaves like a pending action item. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `handle_incoming_introduction_test.dart`, `load_introductions` coverage, and regression case 3. |
| SC-008 | `passed`, `expired`, and `alreadyConnected` never regress to pending because of stale delivery | A terminal intro later receives stale messages. | 1. Seed terminal states. 2. Deliver stale messages after the fact. | Terminal truth is preserved across all stale deliveries. | P0 | Required | Required | N/A | Required | Recommended | Inventory: Covered on 2026-04-09 by the stale-send terminal-state regressions in `handle_incoming_introduction_test.dart` for `passed`, `expired`, and `alreadyConnected`, plus a green rerun of `./scripts/run_test_gates.sh intro`. |
| SC-009 | Same-pair dedupe semantics are stable across same introducer and different introducer cases | A pair can be introduced repeatedly over time. | 1. Re-introduce with same introducer. 2. Repeat with a different introducer after connection. | Same introducer uses newer-wins replacement; different introducer after connection yields `alreadyConnected` without duplicate contacts. | P0 | Required | Required | N/A | Recommended | Required | Inventory: Covered by `handle_incoming_introduction_test.dart`, `introduction_smoke_test.dart`, and `introduction_multi_node_test.dart`. |
| SC-010 | State isolation holds across multiple intro chains and multiple `introductionId` values | Several intro chains coexist. | 1. Interleave sends/responses across unrelated introIds. | Only the matching intro row mutates for a given envelope; no cross-chain bleed occurs. | P0 | Required | Required | N/A | Recommended | Recommended | Inventory: Covered logically by `mutual_acceptance_test.dart` and multi-node chain/circular flows. |
| SC-011 | Pending badge counts only truly pending intros | User has pending, alreadyConnected, expired, and passed intro rows. | 1. Load badge count and intro list. 2. Modify statuses and reload. | Badge count tracks only actual pending rows; list may include alreadyConnected context without badge inflation. | P0 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by `handle_incoming_introduction_test.dart`, `orbit_intros_wiring_test.dart`, and regression case 3. |

## UX, Orbit, Notifications, and Cross-Feature Coverage

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UX-001 | Orbit intro review renders grouped intros and the correct pending count | User has one or more intros from one or more introducers. | 1. Open Orbit. 2. Inspect grouping, headers, and count. | Rows are grouped by introducer; pending count matches repository truth. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by the OrbitScreen intro-review widget regression in `orbit_screen_archived_groups_test.dart`, the existing wiring checks in `orbit_intros_wiring_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-002 | IntroRow copy and actions are exact for pending, waiting, passed, alreadyConnected, and mutualAccepted states | Intro rows exist in each status variant. | 1. Render each state. 2. Inspect buttons, labels, and CTA copy. | Pending shows Accept/Pass; one-sided accept shows waiting; passed shows Passed; alreadyConnected shows correct badge; mutualAccepted shows `Message` CTA. | P0 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by `intro_row_test.dart` state coverage for pending/waiting/passed/alreadyConnected plus the new exact `Message` CTA regression, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-003 | FriendPickerWired full flow: loading, search, selection, send, progress, and navigation callback | Conversation can open the friend picker and A has candidate contacts. | 1. Open picker. 2. Search/filter. 3. Select friends. 4. Send. 5. Observe progress and callback. | Picker shows correct states, sends intros, and returns the expected callback payload to the parent flow. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by the full-flow `FriendPickerWired` regression in `friend_picker_wired_test.dart`, the existing wired filtering/reintroduction checks, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-004 | SentConfirmationWired end-to-end matches the sent result set | A just sent one or more intros. | 1. Finish send flow. 2. Land on confirmation. 3. Use back-to-conversation action. | Confirmation screen shows correct names/count and routes back cleanly. | P2 | N/A | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by the dedicated `SentConfirmationWired` wrapper regression in `sent_confirmation_wired_test.dart`, the existing pure screen assertions in `sent_confirmation_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-005 | Conversation banner and overflow entry remain consistent after dismiss, introsSentAt, block/unblock, and message-count changes | A is in a 1:1 conversation eligible for intros. | 1. Toggle each gating condition. 2. Inspect both banner and overflow entry. | Banner and overflow stay truthful to the same effective eligibility model without drifting apart. | P1 | Required | Required | N/A | N/A | Recommended | Inventory: Covered by banner tests, overflow tests, dismiss tests, and intro wiring smoke. |
| UX-006 | New-intro and mutual-accept notifications use the correct title/body content | Local or push-backed intro notifications are enabled. | 1. Receive a new intro. 2. Reach mutual acceptance. 3. Inspect emitted notification content. | Notification title/body clearly identify intro review vs new connection and use the correct perspective. | P1 | Recommended | Required | N/A | N/A | Required | Inventory: Covered on 2026-04-09 by the exact local-notification copy assertions in `introduction_listener_test.dart`, the new intro-fallback copy regressions in `background_push_notification_fallback_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-007 | Notification deep-link opens Orbit intros and preserves shell return behavior | An intro notification was received and tapped. | 1. Tap intro notification from background or shell context. 2. Return to prior shell state. | App lands on the intros review surface and restores prior shell/tab behavior when backing out. | P1 | N/A | Required | N/A | N/A | Required | Inventory: Covered by `intro_notification_orbit_route_test.dart`, `chat_and_group_push_open_flow_test.dart`, and background push tests. |
| UX-008 | Feed connection card reflects introducedBy metadata and blocked state | B and C connected through an intro and the feed renders the event. | 1. Render the connection card. 2. Repeat with blocked state enabled. | Feed card shows both usernames, introducer attribution, correct CTA behavior, and blocked overlay/disable state. | P2 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered by `introduction_connection_card_test.dart` and feed-mapping assertions. |
| UX-009 | Mixed-script, RTL, long, and null usernames render correctly across intro UI surfaces | Intro UI includes usernames with varied scripts and fallbacks. | 1. Render rows, headers, system messages, and confirmation with mixed-script/null/long names. | Directionality, fallbacks, and truncation stay correct and explicit across intro surfaces. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered across `intro_row_test.dart`, `intro_group_header_test.dart`, `intro_system_message_test.dart`, `intros_tab_extended_test.dart`, and `sent_confirmation_test.dart`. |
| UX-010 | Orbit live refresh reacts to introReceived, status changes, and delete actions | Orbit is open while intro state changes arrive. | 1. Receive a new intro. 2. Accept or pass. 3. Delete an intro row. 4. Observe counts and grouped data. | UI refreshes live with correct counts, rows, and route-return flags. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered by `orbit_intros_wiring_test.dart` and intro-related `orbit_wired_test.dart`. |
| UX-011 | Orbit intro pending-count banner variant matches the underlying intro state | Orbit has zero, one, or many pending intros. | 1. Open Orbit across different pending-count states. 2. Inspect banner copy/visibility. | Pending-count banner appears only when appropriate and uses correct count-driven copy. | P2 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered on 2026-04-09 by the OrbitScreen banner regressions in `orbit_screen_archived_groups_test.dart` for zero, singular, and plural pending-intro states, plus a green rerun of `./scripts/run_test_gates.sh intro`. |
| UX-012 | Delete confirmation and cancel flow for intro rows are reliable | User chooses to delete an intro row from Orbit. | 1. Trigger delete. 2. Confirm in one run and cancel in another. | Confirm removes the row and updates badge state; cancel keeps the row and badge unchanged. | P1 | Recommended | Required | N/A | N/A | Recommended | Inventory: Covered by intro-related `orbit_wired_test.dart`. |

## Recommended smoke suite

These are the journeys I would keep **Smoke = Required** for this feature:

- **IL-004** — single intro send creates one shared introId and local row
- **IL-007** — online receipt creates pending intro on B and C
- **RM-003** — one side passes and no contact is created
- **RM-011** — second accept creates exactly one contact on each side
- **RM-014** — first encrypted chat works immediately after mutual acceptance
- **IL-010** — already-connected intro stays non-actionable and does not inflate pending badge
- **DR-011** — offline relay intro delivery converges to mutual acceptance and first chat
- **DR-013** — re-introducing the same pair repairs a missed side and ignores stale delivery

If you want an even smaller release gate, keep the first six and run the last two in nightly fake-network / 3-simulator lanes.

## Notes for implementation

- For every journey that mutates intro state, assert final truth on **A, B, and C together**: intro row, per-party statuses, overall status, contact existence, pending count, and user-visible copy.
- For every dedupe/replay journey, assert **all four layers**: no duplicate intro row, no duplicate contact, no duplicate system message, and no duplicate notification.
- For any transport-sensitive row, make the fake network deterministic: delivery order, retries, partitions, inbox release, and reconnect timing should be explicit test controls, not incidental sleeps.
- For app-resume and crash-recovery rows, snapshot both **sender-side persistence** and **receiver-side delivery**; “remote saw it” is not enough if A did not save its local row.
- For UI rows, keep widget tests as the first line of defense, but still prove one integrated user-visible path for the flows that matter in production.
