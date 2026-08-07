# 344 - GAP-N01 Direct Inbox Non-Destructive Capacity And Mixed-Version Activation

Status: implemented / default-off code-closed 2026-08-07; `$tdd-review` applied; exact concurrency-2 feature-harness and repository-wide formatter baseline caveats recorded below
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5 requirement 3; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01
Classification: implemented; production admission remains separately ops-authorized, evidence-gated, and default-off
Closure tier: host-native relay/protocol/process proof plus Android gomobile binding build; no mobile-device or iOS-device acceptance

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-07 | Evidence Collector | PRD §5/§5.1; GAP-N01 report; Plans 342/343; relay memory/limited/Redis inbox backends, handler, bootstrap, metrics, protocol contract; Go node selector/parser; Go/Dart bridge; P2P receive/stage/ACK path; current gates; NET-REL-07; FDC-10 runbook | Confirmed the release blocker: DB v108/v109 transfer custody on typed `stored|duplicate`, while every production legacy direct-inbox backend evicts the oldest unacknowledged row at capacity and returns `stored`. The existing `rejected_full` plumbing is present but unreachable on those backends. | Define a compatible non-destructive lane and prove old/new sender, receiver, and relay combinations. |
| 2026-08-07 | Planner | Same source plus retry/feed/bootstrap bypasses, Redis/process fixtures, local two-relay libp2p harness, native binding scripts, and relay ops artifacts | Chose three additive actions on the frozen protocol, a physically separate ACK-or-expiry lane, and an atomic legacy compatibility shadow. This avoids a recipient-capability registry while preventing legacy store/retrieve and old-binary rollback from deleting protected rows. | Save the draft, run `$tdd-review`, and apply only source-backed corrections. |
| 2026-08-07 | Independent reviewers + arbiter | Draft v1; 128 KiB response fitting; ten-page receiver ceiling; legacy-to-upgraded replay; Redis/miniredis lifecycle; async push; bridge singleton; v108/v109 call graph, mixed-relay selection, and gates | Initial verdict `plan-fixes-required`. Replaced protected-first/four-page reasoning with stable cross-lane FIFO and oversized-page continuation; added sequential old-receiver/upgrade convergence, per-relay retrieve/ACK negotiation and bounded fanout, strict proof ownership, narrow wire/error and eligibility contracts, honest process/old-binary claims, exact caller/gate discovery, and removed production memory-lane work. | Execute the reviewed contract tests-first; keep live rollout and iOS runtime evidence deferred. |

## Problem And Evidence

- Behavior to improve: a sender using the Plan 342 direct-text or Plan 343 direct-reaction outbox must transfer custody only to a relay row that remains until exact recipient ACK or the existing seven-day expiry. At capacity, the newest distinct obligation must remain sender-owned; no older accepted obligation may be evicted.
- Impact: today a full relay can acknowledge the newest write, causing the sender to delete its DB v108/v109 row, while silently deleting the oldest unacknowledged relay row. That is a real event-loss window and directly contradicts PRD §5 requirement 3 and GAP-N01.
- Confirmed root cause: `memoryInboxBackend.Store`, `memoryInboxBackendLimited.Store`, and `redisInboxBackend.Store` evict oldest before append and return `InboxStoreResultStored` (`go-relay-server/backend_memory.go:114-153`; `go-relay-server/limits.go:96-154`; `go-relay-server/backend_redis.go:263-327`). `TestStatusValueContract_FullInboxStoreStaysOK` freezes that behavior for installed clients (`go-relay-server/protocol_contract_test.go:205-273`).
- Confirmed sender consequence: the v108 and v109 drains retire exact local rows after `InboxStoreOutcome.accepted`, which means only `stored|duplicate` (`lib/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart:74-110`; `drain_direct_reaction_inbox_custody_outbox_use_case.dart:33-75`). Under the current relay, `stored` does not mean ACK-or-expiry retention.
- Existing reusable coverage: stable relay entry IDs, non-destructive `retrieve_pending`, stage-before-ACK replay, exact ACK, paging, expiry, namespaced target/edit/reaction dedupe, typed full parsing, store-before-push, duplicate-no-refanout, multi-relay selection, Redis shared-state/process fixtures, and DB v108/v109 exact-envelope CAS are already present.
- Existing compatibility rail: NET-REL-07 permits a new action and additive response field but forbids changing the old protocol ID, existing action/status semantics, or Redis names in a way that orphans current rows (`Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md`). Therefore changing legacy `store` from `OK` to `ERROR`, or putting protected rows in the legacy queue, is not valid.
- Confirmed mixed-version hazard: legacy `retrieve` is destructive (`go-relay-server/backend_memory.go:188-217`; `backend_redis.go:330-375`). A protected marker inside the existing record/queue would still be removed by an old client or an old relay binary, and legacy overflow would still evict it.
- Confirmed bypasses: fresh text can fall back from typed to bool inbox storage, and v108 failed-message/feed retries can wrap bool `true` as `stored` (`send_chat_message_use_case.dart:398-402,1097-1149`; `retry_failed_messages_use_case.dart:279-303,445-485`; `feed_wired.dart:2363-2418`). Reactions fail closed on a typed capability today, but that capability proves only the legacy store contract.
- Confirmed deployment constraint: the relay defaults to in-memory and only Redis is durable (`go-relay-server/server_bootstrap.go:21-29,55-151`). FDC-10 requires every front-end to share one Redis URL/prefix and currently documents an unsafe rollback-to-memory option that must be narrowed once protected custody is admitted.
- Missing coverage: no test proves non-destructive at-cap behavior, exact protected receipt, protected/legacy isolation, atomic shadow creation, mixed old/new relay fallback, old-receiver-to-upgraded replay convergence, kill-switch draining, or baseline legacy-key namespace preservation.
- Refuted findings: changing the existing `store` result to `rejected_full` is not compatible; a request field on legacy `store` is not proof because an old relay ignores it and returns generic `OK`; a new protocol/action sharing the old queue is not protected; a second local scheduler or DB migration is not needed.
- Unresolved findings: production traffic thresholds, configured Redis AOF/RDB/HA plus real restart/restore evidence, the pinned rollback artifact, and the exact activation date are ops decisions and are not invented here. The code plan can become deployable/default-off without authorizing SSH, a relay restart, or production admission.
- Affected production/test/gate files: relay inbox/store/backends/bootstrap/main/metrics and ops docs; Go node inbox parser/actions/selector tests; the existing Go bridge `InboxStore` parameter/result seam; Dart inbox outcome/P2P coordinator capability; Plans 342/343 send/drain/retry/bootstrap callers; focused relay/Go/Dart tests and `scripts/run_test_gates.sh` registration.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `a6798bd775bd0331`; current at planning time.
- Query / profile: `python3 graphify-arch/tdd_context.py query "InboxProtocol TestStatusValueContract_FullInboxStoreStaysOK parseInboxStoreResponse InboxStoreResultRejectedFull direct_inbox_custody_outbox direct_reaction_inbox_custody_outbox TRANSPORT_TESTS" --profile tdd --budget 700`.
- Anchors: `TestStatusValueContract_FullInboxStoreStaysOK` -> `go-relay-server/protocol_contract_test.go:213`; `parseInboxStoreResponse` -> `go-mknoon/node/inbox.go:82`; `TRANSPORT_TESTS` -> `scripts/run_test_gates.sh:805`.
- Surfaced proof/gate files: relay protocol/dedupe/parser tests, server bootstrap, Go node inbox parsing, and the transport gate inventory.
- Graph gaps requiring source search: Go backend implementations, bridge code, DB v108/v109 callers, Redis process fixture, local multi-relay harness, native bindings, ops docs, and exact curated registration were verified directly.
- Reuse rule: these anchors may be handed to review/execution; every conclusion still requires current-source or command evidence.

## Scope Contract And Guard

In scope:

- Keep `InboxProtocol == "/mknoon/inbox/1.0.0"` and every existing request/response behavior frozen. Add exactly three actions to the existing lenient JSON protocol: `store_custody_v1`, `retrieve_custody_pending_v1`, and `ack_custody_v1`. Old relays deterministically reject those unknown actions; old clients never send them.
- Add the response proof `custodyContract: "ack_or_expiry_v1"`. A sender may retire a DB v108/v109 row only when the new store action returns exact `stored|duplicate` plus this exact proof. Add `InboxStoreOutcome.ackOrExpiryAccepted` (or an equivalently narrow predicate) and require each v108/v109 owner to use it; generic `accepted` remains the legacy predicate. Generic `OK`, a missing/mutated proof, a legacy `stored`, disabled admission, full, malformed response, timeout, or transport error is non-accepting and follows the retry rules in the wire table; identity conflict/ineligibility stops terminally. No non-proof outcome retires local custody.
- Use existing bridge commands/exports rather than add a platform method. Extend `Bridge.InboxStore` JSON with optional `custodyContract` and `custodyKind`: both absent is byte/behavior-compatible legacy storage; exact `custodyContract:"ack_or_expiry_v1"` requires exact `custodyKind:"direct_text_v108"|"direct_reaction_v109"` and selects strict store; a partial/unknown pair is invalid. Extend existing retrieve-pending and ACK payloads with optional `custodyContract`; absent preserves legacy first-success node methods, while exact `ack_or_expiry_v1` selects new all-peer methods and exact response proof. This avoids Android/iOS/macOS wrapper churn and preserves old bridge callers.
- Introduce a separate optional Dart capability, `AckOrExpiryInboxStore`, and `StoreInAckCustodyInboxDetailedFn` whose call requires the two-value custody kind. `P2PServiceImpl` implements it. Keep `DetailedInboxStore`, `P2PService.storeInInbox`, `storeInInboxDetailed`, and every unrelated bool/legacy caller unchanged.
- Route only Plan 342 DB v108 fresh-direct-text custody and Plan 343 DB v109 direct-reaction ADD/REMOVE custody through the new capability: immediate sends, exact lifecycle drains, the v108 failed-message route, the feed composer retry route, and production bootstrap composition. Remove their bool/generic-typed fallback. Keep `verifyInboxCustody`, private/disappearing media, edits/deletes outside v108 authority, receipts, contact/group flows, and all other callers on legacy semantics. Use limited purpose-built strict fakes/adapters in tests; do not make every `P2PService` fake implement the new capability.
- Add a physically separate protected backend lane only to the production Redis backend. Keys are exactly `${REDIS_PREFIX}custody_inbox:<encoded-peer-id>` and must not match legacy `${REDIS_PREFIX}inbox:*`; a narrow in-memory test backend may exercise the contract, but the production memory/limited backends stay legacy-only and cannot enable admission. Protected capacity reuses `MaxInboxMessagesPerPeer`; it does not add a second tunable. During transition the bounded total can be at most one protected cap plus one legacy cap per peer.
- Add the exact additive node/relay request field `custodyKind` and a protected-specific eligibility parser rather than reuse broad `extractDirectInboxDedupeKey`: `direct_text_v108` accepts only the exact v2 encrypted `chat_message` outer shape with a nonblank target ID, authenticated matching sender, complete encrypted fields, and no edit `eventId`; `direct_reaction_v109` accepts only the already-exact v2 reaction ADD/REMOVE shape and `reaction-event-id:` identity. The relay cannot inspect encrypted inner media policy, so semantic ordinary-text ownership remains client-side and is source/behavior locked; the explicit discriminator plus structural parser prevents accidental edits, deletes, contacts, groups, malformed messages, and generic bridge calls from entering the lane. Known excluded shapes change neither lane nor push state.
- The protected identity tuple is recipient + eligible namespaced key + authenticated stream sender + byte-exact envelope. Same exact tuple is `duplicate` even at cap. Same key with changed sender or bytes is `CUSTODY_IDENTITY_CONFLICT`. A new distinct tuple at protected cap is `rejected_full`; it changes neither lane and launches no push.
- Commit a new protected row and a compatibility shadow to the legacy lane in one Redis transaction, with the same random relay entry ID and timestamp. The protected row is authoritative. The shadow is compatibility-only, obeys the frozen legacy evict-oldest limit, and is the only row visible to legacy retrieve actions/old binaries. Only after the combined commit may the existing asynchronous push launch decision run. Plan 344 guarantees no duplicate refanout and at most one launch during a live relay process; it does not add a durable push outbox or claim a launch survives a post-commit process crash.
- Handle ambiguous pre-activation delivery: if the same exact identity/sender/bytes already exists only in the legacy lane and is not expired, atomically copy that existing ID/timestamp into protected custody, leave the legacy row as its shadow, return `duplicate` with the exact proof, and do not refanout push. Never promote an expired legacy row. If protected capacity is full or the legacy identity conflicts, retain the sender row. Exact duplicate responses preserve the original protected timestamp/expiry.
- `retrieve_custody_pending_v1` coalesces a protected row and its same-ID, same-sender, byte-equal shadow, then returns one stable global oldest-first order across protected and legacy-only logical rows (timestamp, then entry ID), not a protected-first concatenation. Reuse `fitRetrievePendingResponse`; the 128 KiB frame budget may return fewer than the requested 50. Near-frame-limit tests must prove each successful ACK advances the stable prefix, `hasMore` survives trimming, and later existing lifecycle drains eventually reach both lanes within the unchanged ten-pages-per-invocation ceiling. Do not add a durable pagination cursor or raise that ceiling in this plan.
- `ack_custody_v1` removes each requested exact entry ID from both lanes atomically in the production Redis transaction (or one lock in the test backend) and reports the number of unique IDs removed, not the sum of physical copies. Unknown/blank IDs change nothing. Existing `retrieve_pending`, `ack`, and destructive `retrieve` remain legacy-only and byte/behavior-compatible.
- Add strict Go receive/ACK methods selected by the exact optional bridge contract, with bounded fanout over every configured relay peer; preserve existing first-success node methods for absent-contract callers. For each relay peer, try the new retrieve action, use a valid `OK`/`NO_MESSAGES` response for that peer, and otherwise try legacy `retrieve_pending` on that same peer. One upgraded empty response is not global emptiness. Exact-coalesce/sort the union, fail closed on same-ID/different-sender-or-bytes, return at most the existing 50-row/128 KiB logical page, and set `hasMore` when any source has more, the merged union was trimmed, or a nonempty partial result accompanied a failed relay. If all valid responses are empty, success requires every configured relay peer to have answered validly; an empty partial scan is an error and retries later.
- After durable stage/replay, the strict ACK method fans out the returned entry IDs to every configured relay peer, using new `ack_custody_v1` per capable peer and same-peer legacy `ack` fallback otherwise. Any relay failure or aggregate count below the requested logical count returns nonacceptance after best effort; successful shared/duplicate physical removals report at most the requested unique count. Existing idempotent staging/replay makes partial ACK safe on retry. This needs no relay-source DB column, durable cursor, new bridge command, or platform API. Never fall back from a custody **store** to legacy store. Existing Dart SQLCipher staging/replay still precedes ACK, so no DB v110 is added.
- Preserve seven-day expiry. Protected rows are removed only by `ack_custody_v1` or expiry. A legacy shadow may be evicted or destructively read earlier without changing protected custody. Promotion preserves the original timestamp/expiry rather than extending custody.
- Add `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED`, default false. It gates new stores only; protected retrieve, ACK, expiry, and metrics remain available while off. Starting with admission enabled on a memory backend fails loudly. Production activation requires every front-end on the same durable Redis and contract revision.
- Add fixed-cardinality observability through the existing stats ticker: contract-revision info, admission-enabled gauge, accurate protected-pending gauge, protected expiry counter, and protected store results (`stored|duplicate|rejected_full|disabled|identity_conflict|ineligible|failed`). Keep IDs/envelopes out. `relay_inbox_capped_total` and existing expiry counters remain physical legacy/shadow events only; protected full increments rejection, not capped, and protected expiry is not double-counted.
- Update `go-relay-server/README.md`, NET-REL-07, the FDC-10 rollback section, and the existing Grafana dashboard. The plan's state machine is the rollout runbook; do not add a dynamic flag service, percentage allocator, admin endpoint, or a second dashboard system.

Wire outcome contract for the additive actions:

| Relay/network result | Required new-action shape | Store selector / local v108-v109 result | Retrieve/ACK behavior |
|---|---|---|---|
| Protected `stored` or exact `duplicate` | `status:"OK"`, exact `storeStatus`, `custodyContract:"ack_or_expiry_v1"`; duplicate preserves original expiry | Accept and stop; only `ackOrExpiryAccepted` may retire the exact row | N/A |
| Protected capacity full | `status:"ERROR"`, `storeStatus:"rejected_full"`, `errorCode:"INBOX_FULL"` | Continue other relays; if none accepts, retain with existing `store_rejected_full` classification | N/A |
| Admission disabled | `status:"ERROR"`, `errorCode:"CUSTODY_ADMISSION_DISABLED"` | Continue other relays; retain as existing `store_failed` if none accepts | Reads and ACK remain enabled |
| Identity conflict / ineligible shape | `status:"ERROR"`, exact `CUSTODY_IDENTITY_CONFLICT` or `CUSTODY_INELIGIBLE` | Terminal fail-closed for this operation and retain as existing `store_failed`; never route around it or reinterpret it as duplicate | N/A |
| Old relay unsupported | exact legacy `status:"ERROR"`, `error:"Unknown action: <requested-action>"`, no proof | Continue; after all store attempts, retain. Never call legacy store | On that relay peer, use legacy pending/ACK, then continue the pool fanout |
| `OK` with absent/unknown proof, malformed JSON/status, or transport failure | no valid custody receipt | Continue; then retain as existing `store_failed` (`store_threw` only for the existing caller exception path) | Try same-peer legacy pending/ACK; if neither is valid, record that relay failed and apply partial/empty rules |
| New retrieve `OK`/`NO_MESSAGES`, or new ACK `OK` | exact action response plus `custodyContract:"ack_or_expiry_v1"` | N/A | Complete that relay peer's leg only; continue all remaining relay peers and do not also invoke legacy action on this peer |

The Go node parser owns this table. Store remains first-valid-proof selection; retrieve and ACK are all-peer operations. The bridge/Dart layers preserve the distinctions without inventing new database error codes or a migration.

Must preserve:

- Frozen legacy at-cap `OK` plus evict-oldest behavior -> `TestStatusValueContract_FullInboxStoreStaysOK`, memory/limited/Redis legacy overflow tests, and old-client handler smoke.
- Legacy destructive retrieve, pending/ACK, response keys/status values, protocol ID, push payload keys, wake-token authorization, store-before-push, and duplicate-no-refanout -> TC-344-01/03/04/11.
- Plan 342/343 atomic local staging, exact-envelope CAS, lifecycle cadence, retry isolation, relay target/edit/reaction namespaces, and receiver parity/dedupe -> TC-344-07/08/09.
- Old sender -> new relay stays legacy. New sender -> old relay never receives a false custody proof. New sender -> new relay -> old receiver gets the legacy shadow while protected custody survives. New receiver -> new relay stages once then exact-ACKs both copies -> TC-344-06/11.
- New clients keep working during a mixed relay pool: old/disabled relay errors are retryable; an enabled relay can accept. A received legacy `OK` is never a protected success -> TC-344-06/11.
- Admission kill switch never disables reads/ACKs for rows already accepted -> TC-344-05/10.
- Android and iOS share the same Go source and existing bridge export. This plan proves host Go behavior and rebuilds/verifies Android bindings; it makes no iOS runtime/device parity claim -> Device/Relay Proof Profile.

Hard `Do not`:

- Do not change `InboxProtocol`, legacy `store|retrieve|retrieve_pending|ack`, existing status strings/keys, current legacy Redis key, or current old-client at-cap behavior.
- Do not store protected markers inside legacy records, share a single evictable queue, accept an optional field on legacy `store` as proof, or let an old binary scan protected keys.
- Do not delete a sender DB v108/v109 row on generic `OK`, direct/live ACK, shadow creation alone, push acceptance, or a response without the exact custody contract.
- Do not add DB v110, a generic event ledger, a recipient capability registry, a second retry scheduler, background worker, new provider payload, or event-lane expansion.
- Do not route media, edits/deletes, groups, receipts, contact flows, or arbitrary `storeInInbox` calls into the protected lane.
- Do not deploy/restart a live relay, set the production flag, mutate live Redis, add SSH automation, or claim production activation without separate user authorization.
- Do not add an iOS device/simulator/APNs/NSE harness leg. If implementation needs a new native platform method rather than the existing bridge export, stop and re-review the platform boundary.

Deferred / accepted difference:

- Protected and legacy each retain the configured cap during transition, for a maximum bounded 2x direct-inbox rows per peer -> accepted rollout overhead; remove only after old-client traffic retirement is separately evidenced.
- Legacy shadows may still evict/destructively disappear under the frozen old-client contract; protected rows remain authoritative and recover when a new receiver version arrives -> intentional compatibility bridge.
- There is no historical backfill: pre-activation legacy-only rows and stores made by old clients retain the legacy eviction risk. Plan 344 protects only v108/v109 owners after the Redis capability is enabled and capable clients use it; fleet saturation/drain evidence remains a later rollout gate.
- The inherited asynchronous push launch has a commit-to-launch crash window. Plan 344 prevents duplicate refanout but deliberately does not add a durable push outbox; provider wake/alert reliability remains in the later notification wave.
- Media, edit/delete, group ordering/truthfulness, device fanout, generic provider wake, outcome ledger, and presentation arbitration -> later GAP-N01/N02/N03 plans.
- Production build/revision selection, traffic window, alert thresholds, canary cohort, staging/live Redis smoke, and actual relay deployment -> separate ops authorization after code closure.
- Consolidated iOS binding refresh/runtime/APNs evidence -> GAP-N12 after GAP-N01 through GAP-N11 code and Android evidence are complete. Automatic Xcode digest rebuild remains the compile-safety mechanism meanwhile.

Dependencies:

- Plans 342 and 343 are implemented at baseline commit `6bab4c485dd4d13887392915abaaaabf85ea4b21`.
- Relay binary rollout precedes client rollout. The safe state sequence is S0 old binary -> S1 new binary/admission off/Redis/drain support -> S2 new binary/admission on on every front-end/old clients unchanged -> S3 capable clients use protected store.
- S2 requires ops evidence that every front-end shares the same Redis URL/prefix and that the deployed Redis persistence/HA policy (AOF/RDB as configured) survives an actual restart/restore. Miniredis and relay-process handoff prove code ownership, not Redis-server durability.
- S3 kill switch returns to S1: reject new protected stores so senders retain local rows, while continuing to retrieve/ACK/expire existing protected rows.
- Baseline-source namespace proof shows legacy code constructs only `${REDIS_PREFIX}inbox:<peer>` and cannot address `${REDIS_PREFIX}custody_inbox:<peer>`; the hermetic helper is a current legacy-only process, not a frozen deployed binary. A pinned old-binary emergency rollback still requires ops evidence, pauses protected retrieval, and makes new stores fail closed. Once protected pending is nonzero, normal rollback is flag-off or a compatibility binary; old-binary rollback is not service-equivalent.
- Full `host-all` plus full Go/relay wave closure remains owned by the GAP-N01/N02/N03 dependency wave and final rollout/release.

## Test Contract

Every row is required. Subtests named below are part of the named parent test and may not be silently omitted.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-344-01 | New actions/proof/eligibility are additive; ineligible envelopes have no lane/push effect; every legacy protocol/status/full-inbox contract is frozen | `go-relay-server/protocol_contract_test.go::TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction`; `::TestRelayNotificationClosure_AckCustodyEligibilityIsNarrow`; `::TestStatusValueContract_FullInboxStoreStaysOK`; `::TestProtocolIDContract_Frozen`; `::TestResponseKeyContract_Frozen` | Host Go; real stream handler, production legacy memory store, narrow protected test backend | HEAD returns `Unknown action` -> GREEN exact text/reaction discriminators accept, edit/delete/contact/group/malformed/generic shapes do nothing, new full rejects without eviction, and legacy store still returns OK/evicts | Reuse broad dedupe extraction, route new action to legacy `Store`, or mutate frozen wire values -> causal/sentinel red | Exact focused selector; closure-prefix parents enter `run_relay_notification_go_gate` / `1to1` |
| TC-344-02 | Redis protected custody is duplicate-before-cap, non-evicting, exact-identity, ACK/expiry-only, and race safe | `go-relay-server/ack_custody_backend_test.go::TestRelayNotificationClosure_AckCustodyBackendContract` subtests `redis`, `duplicate_at_full_preserves_expiry`, `expired_legacy_not_promoted`, `identity_conflict_sender_or_bytes`, `concurrent_same_key_different_bytes_one_winner`, `concurrent_distinct_at_last_slot` | Host Go; production Redis backend + miniredis, deterministic clock/barriers; narrow in-memory contract double only | HEAD has no lane -> GREEN oldest remains, exact duplicate works at cap, expired rows do not resurrect, conflicts never split shadow/protected identity, and capacity admits at most one winner | Evict, cap-check before duplicate, compare ID alone, refresh expiry, or split race checks -> named subtest red | Exact parent, closure prefix -> `1to1` |
| TC-344-03 | Protected row and same-ID legacy shadow commit atomically before an at-most-once live-process push launch; exact legacy promotion does not refanout | `go-relay-server/ack_custody_shadow_test.go::TestRelayNotificationClosure_AckCustodyProtectedShadowAtomicity` | Host Go; production Redis transaction + deterministic test backend, failpoints, recording push sender | HEAD cannot create protected state -> GREEN successful new store exposes equal ID/time copies and one launch; exact unexpired promotion preserves ID/time/expiry and launches zero; known pre-commit/transaction-abort failures expose neither new copy; ambiguous post-EXEC response loss is non-accepting locally but may leave both copies, and exact retry returns duplicate/no refanout | Split writes, launch before commit/on duplicate, mint during promotion, promote expired row, or treat an ambiguous error as proof -> red | Exact parent, closure prefix -> `1to1` |
| TC-344-04 | New pending coalesces exact shadows, uses stable global FIFO across lanes, reuses frame fitting, and new ACK reports/removes unique IDs; legacy reads stay legacy-only | `go-relay-server/ack_custody_retrieval_test.go::TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation`; preservation `inbox_test.go::TestHandleInboxStream_RetrievePendingTrimsOversizedResponses` | Host Go; real handler + Redis/test backend; alternating timestamps and near-frame-limit envelopes | HEAD actions absent -> GREEN old destructive/pending/ACK affects only shadows; exact coalesce emits one row; mismatched sender/bytes never coalesce; ACK removes both copies/counts one; oversized pages preserve FIFO/`hasMore`, and repeated ACKed drains eventually expose both lanes | Protected-first concatenation, physical-copy ACK count, no response fitter, or legacy access to protected keys -> red | Exact new parent plus named existing frame sentinel; closure prefix -> `1to1` |
| TC-344-05 | Protected state survives relay-process handoff through shared Redis; admission-off drains; baseline legacy namespace cannot address protected keys; re-enable preserves expiry | `go-relay-server/redis_failover_integration_test.go::TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace` | Host cross-process Go; one persistent miniredis instance, helper processes using production codecs, current legacy-only mode + baseline source contract | HEAD has no state -> GREEN process A stores, process B flag-off retrieves/ACKs; legacy-only operations can delete/evict shadow only; reopen sees original expiry | Share `inbox:` prefix, gate read/ACK, use process memory, or refresh expiry -> red | Tagged exact selector + non-skip/list proof in `run_ack_custody_go_gate`; explicitly not Redis-server restart or frozen-binary evidence |
| TC-344-06 | Go store parser implements every wire outcome and store fails closed; receive/ACK negotiates and fanouts per relay so one empty upgraded relay cannot mask an old relay row | `go-mknoon/node/inbox_ack_custody_test.go::TestInboxAckCustodyMixedRelayAndProofContract`; `::TestInboxAckCustodyReceiveFanoutContract` | Host Go; production parser/selector with raw old/disabled/full/conflict/ineligible/generic/malformed/new responders, disjoint relay state, large rows | HEAD has no strict method -> GREEN exact proof alone accepts; conflict/ineligible is terminal; store never legacy-falls back. Receive fixture `[new empty, old with row]` returns/stages the old row; `[new row, old row]` stable-merges/trims; global empty requires all-peer valid emptiness; same-ID mismatch fails; ACK reaches new and old peers and partial failure remains retryable | Accept generic OK, route around conflict, use first-success receive/ACK, treat partial empty as global empty, omit same-peer fallback, or legacy-fallback store -> red | Exact `-list`, non-skip PASS, then registration in `run_ack_custody_go_gate` / `1to1` |
| TC-344-07 | Existing store/retrieve/ACK bridge exports and Dart capability carry/select exact contract without a new platform API or global test hook | `go-mknoon/bridge/inbox_ack_custody_test.go::TestDispatchInboxAckCustodyContract`; `test/core/bridge/p2p_bridge_client_test.dart::{ack-or-expiry store uses existing command and exact contract,ack-or-expiry retrieve and ack use existing commands}`; `test/core/services/p2p_service_impl_test.dart::ack-or-expiry capability rejects generic OK` | Host Go + Dart; pure unexported contract dispatcher with injected closures after singleton resolution, fake Bridge, production parser/coordinator | HEAD ignores proof -> GREEN exact store pair dispatches strict store, exact receive/ACK contract dispatches all-peer methods and returns proof, absent stays legacy, unknown/partial fails, and unproven store has `ackOrExpiryAccepted == false` | Add a platform command/global singleton hook, route absent receive into fanout, ignore field, or reuse generic `accepted` -> red | Go exact `-list`/non-skip run; Dart full files; existing Dart files remain `ONE_TO_ONE_TESTS` |
| TC-344-08 | Every v108/v109 immediate/retry/feed/lifecycle/bootstrap entrypoint uses strict custody and only exact proof retires; named siblings remain legacy | Exact Plan 344 tests in text drain, reaction drain, `test/features/conversation/application/retry_failed_messages_use_case_test.dart::Plan 344 pending v108 retry cannot wrap bool success as protected receipt`, pending-retrier lifecycle wiring, send chat, send reaction ADD, remove reaction REMOVE, `test/features/feed/presentation/screens/feed_focus_test.dart::Plan 344 contact composer retries v108 through ack custody only`, and `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::Plan 344 production composes v108 and v109 drains with ack custody store` | Host Dart; real SQLite where existing tests use it, limited strict/legacy recording fakes, production composition | HEAD generic typed/bool paths can retire/bypass -> GREEN exact proof alone completes; missing capability/generic OK/full/error/throw retains exact bytes with existing error classes; media/edit/delete/verification stay legacy | Restore bool/generic fallback, use `.accepted`, omit retry/feed/bootstrap/ADD/REMOVE, or widen capability -> named red | Run every named file; all direct files remain registered, add/confirm feed/bootstrap discovery; curated `1to1` and `feed` |
| TC-344-09 | Receiver preserves stage/replay-before-ACK and converges across a real temporal old-receiver -> app-upgrade protected redelivery for text and reaction ADD/REMOVE | `test/core/services/p2p_service_impl_test.dart::protected and shadow page stages once before custody ACK` (preservation sentinel); `test/features/conversation/integration/offline_inbox_roundtrip_test.dart::Plan 344 legacy receive then upgraded protected redelivery converges once` | Host Dart; persistent staging/canonical repositories, ordered bridge, notification/unread/reaction spies | Existing stage-before-ACK sentinel is GREEN on HEAD; transition is causal RED because protected redelivery/action is absent -> GREEN old retrieve/stage/replay/legacy ACK deletes shadow, upgraded retrieve replays protected duplicate with zero second canonical insert, unread increment, reaction change, or notification, then protected ACK clears it | ACK before replay, delete staging without canonical duplicate repair, or double side effects after upgrade -> red | Run full two files or exact separate plain names; both remain `ONE_TO_ONE_TESTS` |
| TC-344-10 | Admission defaults off and Redis-only; flag-off drains; fixed metrics/docs lock S0-S3, expiry accounting, persistence prerequisites, and rollback limits | `go-relay-server/ack_custody_rollout_test.go::TestRelayNotificationClosure_AckCustodyRolloutContract`; `scripts/test/relay_ack_custody_rollout_contract_test.sh` | Host Go + shell/source contract; env matrix, Prometheus gatherer, README/NET-REL-07/FDC-10/Grafana fixtures | HEAD has no flag/metrics/runbook -> GREEN memory-on fails, reads survive off, metric labels contain no IDs, protected expiry is separate, and docs distinguish code proof from Redis restart/frozen-binary ops evidence | Default on, permit memory, gate reads, double-count expiry/full, add IDs, or claim miniredis/live rollback proof -> red | Exact test/shell, `bash -n`, `jq empty`; closure prefix and `run_ack_custody_go_gate` |
| TC-344-11 | Old/new sender/receiver/relay protocol combinations negotiate and converge over actual framed libp2p, including disjoint mixed-pool receive state | `go-mknoon/integration/ack_custody_mixed_relay_test.go::TestAckCustodyMixedVersionMatrix` | Host integration Go; actual in-process libp2p hosts and selector with synthetic old/new action handlers; shared and deliberately disjoint state; TC-344-01..05 own production relay semantics | HEAD strict actions unsupported -> GREEN old sender/new handler, new sender/old-only, old-first/new-second store, `[new empty, old legacy row]`, protected+legacy union, old destructive shadow, per-relay ACK, flag-off/re-enable converge | Stop scanning after new empty, expose protected to legacy action, omit shadow, ACK only first peer, or call these production relay binaries -> red | Tagged exact `-list`, exact run, explicit non-skip evidence in `run_ack_custody_go_gate`; synthetic handlers only |
| TC-344-12 | Android binding contains changed shared Go implementation without adding a platform API; app-owned code/gates remain clean | Android binding ensure/verification plus existing command-map/native wrapper sentinels | Host build; gomobile Go 1.25 + available Android SDK/NDK, no device | Proof-only: rebuilt AAR digest changes and exported method set still verifies | Skip rebuild or add unmatched method -> digest/verification fails | `./scripts/ensure_go_android_bindings.sh && ./scripts/verify_gomobile_bindings.sh android && bash scripts/test/go_binding_staleness_contract_test.sh`; not a device claim |

### Test Notes

- TC-344-01 first RED uses a raw request action string against the existing handler, so it fails at runtime as `Unknown action`; it does not need a missing production symbol or compile-only RED.
- TC-344-02 runs both last-slot races: two distinct keys and the same identity with different bytes/senders. Each has one winner, one deterministic rejection/conflict, no split shadow pair, and no eviction. Exact duplicate checks precede capacity and preserve original expiry; expired legacy-only rows are pruned rather than promoted.
- TC-344-03's known-abort failpoints act before commit or force transaction conflict exhaustion; neither may expose a new copy, return a protected receipt, or launch push. A transport error after EXEC is deliberately ambiguous: both copies may exist, the sender retains custody, and retry must return exact protected `duplicate` without a second shadow/push. “One push” means one asynchronous launch observed while the process remains alive, not durable eventual push delivery.
- TC-344-04 coalesces only exact ID + sender + envelope shadows. Its oversized fixtures force response trimming below 50 rows, assert stable oldest-first prefixes and `hasMore`, ACK each returned prefix, then invoke another bounded drain until a row from each lane is observed. This proves progress without the refuted four-page claim or a new cursor.
- TC-344-04/09 discriminator: one logical entry ID and one canonical receiver side effect are present; two physical relay copies and an ACK count of two are absent.
- TC-344-05's “legacy” leg is an independently spawned current-source helper that constructs only the legacy Redis backend against the same miniredis prefix. It proves relay-process handoff and namespace isolation, not Redis-server persistence or execution of the old deployed artifact.
- TC-344-06 distinguishes a valid new `NO_MESSAGES`/ACK response from every invalid/no-response class in the wire table. Store never compatibility-falls back; deterministic identity conflict/ineligibility is terminal, while old/disabled/full/malformed/transport outcomes follow the exact table. Receive/ACK negotiates independently for every relay peer and never treats one successful peer as authority for the rest. The merged node result retains the current 50-row/128 KiB bound; unreturned rows stay unacknowledged and appear on the next call.
- TC-344-07 tests a pure contract dispatcher because `go-mknoon/bridge` owns a concrete singleton node; store/retrieve/ACK exports resolve the singleton/params, then pass same-signature closures into it. Do not add a mutable global node/test hook. Absent receive/ACK contract retains legacy first-success behavior; only the exact contract enters fanout.
- TC-344-08 pins the production composition and feed caller directly; neither is optional or replaced by a broad source search. The strict function normalizes an unproven generic `stored` to failed before downstream callers can consult generic `.accepted`.
- TC-344-09's stage-before-ACK row is a preservation sentinel, not a claimed RED. The causal transition retains process-independent local state across the simulated upgrade and covers text plus reaction ADD and REMOVE, including canonical data, unread, reaction projection, and notification side effects.
- TC-344-10 may assert exact finite metric names/labels and state transitions, not a speculative error-rate or traffic threshold.

## Implementation Steps

1. Snapshot `git status --short`, HEAD, and current Graphify fingerprint. Add TC-344-01's raw-action causal RED and the legacy sentinels first; record the nonzero runtime failure before production edits.
2. Add an optional protected-backend capability beside `InboxBackend`, implemented by production Redis and a narrow deterministic test backend only. Implement exact tuple comparison, duplicate-before-cap, conflict/full/expiry results, protected stats, and `${REDIS_PREFIX}custody_inbox:` keys. Leave production memory/limited backends legacy-only. Stop-if the protected key can match any legacy `inbox:*` access.
3. Implement the Redis atomic protected+legacy-shadow operation. WATCH/read both exact recipient keys and commit both mutations in one transaction; add the smallest multi-key helper needed rather than generalize unrelated Redis code. Reuse legacy cap/eviction rules for the shadow. Known aborts leave neither new copy; an ambiguous post-EXEC error returns no receipt and converges by exact retry. Stop-if any commit can produce only one newly accepted copy; prefer true atomicity rather than add a worker.
4. Add `InboxStore.StoreAckCustody`, the explicit custody-kind discriminator/parser, and a shared post-store push launcher. Validate structural eligibility, namespaced identity, and authenticated sender; preserve duplicate-no-refanout and original expiry; return the exact wire table. Keep `InboxStore.Store` byte/behavior-identical and do not add a durable push worker.
5. Add the three handler actions. Keep existing cases untouched. New retrieve exact-coalesces, globally sorts logical rows by timestamp/ID, pages, and reuses `fitRetrievePendingResponse`; new ACK removes unique IDs across both lanes. Store admission is default-off; retrieve/ACK are never gated by admission.
6. Add local durable-only activation validation, protected metrics via the existing ticker, and log summary. Update README, NET-REL-07, FDC-10 rollback, and Grafana panels with S0-S3/kill-switch plus explicit Redis persistence/old-artifact evidence boundaries. Local boot must reject admission-on without Redis; cross-front-end URL/prefix sameness and actual Redis persistence/HA cannot be code-detected here and remain mandatory S2 ops receipts.
7. Add the Go node strict store/parser plus separate strict receive/ACK methods. Preserve old first-success methods. Store requires exact proof, stops on terminal conflict/ineligibility, selects past retryable old/disabled/full/malformed/transport results, and never calls legacy store. Strict receive/ACK uses bounded all-relay-peer fanout: per-peer new-then-legacy negotiation, exact union/coalesce/stable sort/50-row-plus-byte fit, global-empty only after complete scan, and best-effort all-peer ACK whose partial result remains retryable. Reuse existing relay inventory/address fallback; do not add a scheduler, persisted cursor, or relay-source schema.
8. Extend the existing store/retrieve-pending/ACK bridge JSON parameters and responses with the optional exact contract while retaining command names and absent-contract behavior. Factor only a pure unexported contract dispatcher with injected legacy/strict closures after singleton resolution; add no global hook or platform method. Extend Dart outcome with the exact store proof/predicate, add `AckOrExpiryInboxStore`, and have the production coordinator request strict retrieve/ACK; normalize accepted-looking missing store proof to failed.
9. Rewire only v108/v109 ownership: fresh text/reaction send, drains, failed-message retry, feed retry, and production lifecycle composition. In the shared fresh-send operation choose strict only when `ownsDirectTextInboxCustody`; preserve legacy behavior for every other attempt. Remove bool/generic fallback from strict paths, and pin feed plus bootstrap with mandatory behavioral/source contracts. Keep historical `verifyInboxCustody` and all non-v108/v109 callers legacy.
10. Extend receiver integration without a schema change. First preserve same-page stage/replay-before-ACK. Then model old retrieve -> durable stage/replay -> legacy ACK/shadow deletion -> app upgrade -> protected replay -> protected ACK for text and reaction ADD/REMOVE, proving every canonical/derived side effect remains singular.
11. Add `run_ack_custody_go_gate` to `scripts/run_test_gates.sh`; invoke it from `1to1` and `all`. It lists and then runs exact Go node/bridge, tagged mixed-handler, tagged Redis-process, rollout shell, and Android-binding staleness contracts, and fails on missing or skipped selection. Keep relay tests under the existing `TestRelayNotificationClosure_` selector.
12. Run focused GREEN/mutations, full affected Go modules, curated `1to1`, justified core/feature family sweeps, Android gomobile build/verify, analyzer, diff/format hygiene, and Graphify incremental refresh. Do not run per-plan full `host-all` and do not deploy.

## Risks And Blind Spots

- One-sided protected/shadow commit could strand old receivers or falsely acknowledge -> TC-344-03 plus the Step 3 stop-if.
- Same logical event may already be in legacy after a lost response -> exact promotion with original ID/time and no refanout in TC-344-03.
- Raw-ID collision across target/edit/reaction namespaces or changed ciphertext could be mislabeled duplicate -> exact namespaced identity + authenticated sender + byte comparison in TC-344-02.
- Concurrent last-slot writes could overfill or evict -> barrier/WATCH/mutex proof in TC-344-02.
- Protected-first pagination plus frame trimming could hide legacy-only work past one ten-page drain -> stable global FIFO, existing response fitter, oversized repeated-drain proof in TC-344-04.
- An old relay's generic OK could stop selector fallback -> exact proof parsing and old-first/new-second TC-344-06/11.
- One upgraded relay's valid empty response could mask a row held by another old relay, and first-success ACK could delete only one backend -> per-relay fanout, disjoint-state matrix, complete-empty rule, and partial-ACK retry in TC-344-06/11.
- Existing legacy receiver could delete protected custody -> distinct namespace/actions and old destructive fixture TC-344-04/05/11.
- An old receiver can consume the shadow and clear local staging before upgrade redelivers the protected copy -> temporal text/ADD/REMOVE canonical and notification convergence in TC-344-09.
- Kill switch or rollback could disable drain as well as admission -> TC-344-05/10.
- Shadow eviction metrics could be confused with protected loss -> separate fixed metrics and dashboard wording TC-344-10.
- Lifecycle / derived-state durability: protected state reconstructs from shared Redis after relay-process handoff; actual Redis-server persistence remains a production activation receipt -> TC-344-05/10.
- A crash after Redis commit but before the existing asynchronous push goroutine launches can suppress that wake -> explicitly accepted inherited boundary; no duplicate refanout is proved, and a push outbox is deferred.
- Sibling-surface consistency: all v108/v109 send/retry/drain callers are protected, while named non-custody siblings remain legacy -> TC-344-08.
- Destructive-action side effects: legacy retrieve removes shadow only; protected ACK removes both exact IDs and preserves unknown/sibling rows -> TC-344-04.
- Invariant re-verification under new transitions: admission off/on, ambiguous response loss, relay-process handoff, legacy-only interval, and re-enable re-check proof/capacity/expiry rather than trusting prior state -> TC-344-03/05/10/11.
- Android/iOS parity: the Go mechanism is shared but only Android binding build is closed here. No iOS runtime claim is made; GAP-N12 owns consolidated iOS evidence.

## Gate Cadence

- Per-plan closure:
  - focused TC commands and recorded representative mutations;
  - full `go-relay-server` module because backend, handler, bootstrap, metrics, and compatibility contracts change;
  - full `go-mknoon` `./node ./bridge` packages plus the exact tagged framed-handler integration;
  - `./scripts/run_test_gates.sh 1to1` after the new Go registration and `./scripts/run_test_gates.sh feed` because `feed_wired.dart` changes;
  - `core-host-all` because bridge/P2P/outcome code changes;
  - `feature-host-all` because direct text/reaction send and retry callers change;
  - Android gomobile ensure/verify and standard hygiene.
- Do not run full `host-all` for Plan 344. Run `./scripts/run_host_test_gates.sh host-all` once after the GAP-N01/N02/N03 dependency wave and once at final rollout/release closure; pair those receipts with the full Go/relay gates.
- Shared tests outside feature/core globs: tagged Go integration and `scripts/test/relay_ack_custody_rollout_contract_test.sh` run by exact command and are registered under `run_ack_custody_go_gate`; the bootstrap and feed files must be discovery-confirmed; Android binding proof is also exact.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes separately.
git status --short
git rev-parse HEAD

# First causal RED before production edits: expect non-zero because HEAD replies
# Unknown action / cannot prove non-destructive custody. Legacy sentinels remain green.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction$' \
  -count=1)

# Every new untagged relay parent must exist and emit a non-skipped PASS.
for plan344_relay_test in \
  TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction \
  TestRelayNotificationClosure_AckCustodyEligibilityIsNarrow \
  TestRelayNotificationClosure_AckCustodyBackendContract \
  TestRelayNotificationClosure_AckCustodyProtectedShadowAtomicity \
  TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation \
  TestRelayNotificationClosure_AckCustodyRolloutContract; do
  (cd go-relay-server && \
    GOTOOLCHAIN=go1.25.0 go test ./... -list "^${plan344_relay_test}$" | \
      rg -x "${plan344_relay_test}")
  (cd go-relay-server && set -o pipefail && \
    GOTOOLCHAIN=go1.25.0 go test ./... -run "^${plan344_relay_test}$" \
      -count=1 -v | rg "^--- PASS: ${plan344_relay_test} \\(")
done

# Focused relay GREEN; expect exit 0 and zero failures.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run 'TestRelayNotificationClosure_AckCustody|TestStatusValueContract_FullInboxStoreStaysOK|TestProtocolIDContract_Frozen|TestResponseKeyContract_Frozen' \
  -count=1)

# Cross-process relay handoff/shared-Redis proof. Discovery and PASS output are
# both mandatory; this is not a Redis-server restart or frozen-binary claim.
(cd go-relay-server && \
  GOTOOLCHAIN=go1.25.0 go test -tags integration ./... \
    -list '^TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace$' | \
    rg -x 'TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace')
(cd go-relay-server && set -o pipefail && \
  GOTOOLCHAIN=go1.25.0 go test -tags integration ./... \
    -run '^TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace$' \
    -count=1 -v | \
    rg '^--- PASS: TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace')

# Full affected relay module; justified by storage/handler/bootstrap/metrics edits.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)

# Native parser/selector/bridge discovery and non-skip PASS are mandatory.
(cd go-mknoon && \
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -list '^TestInboxAckCustodyMixedRelayAndProofContract$' | \
    rg -x 'TestInboxAckCustodyMixedRelayAndProofContract')
(cd go-mknoon && \
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -list '^TestInboxAckCustodyReceiveFanoutContract$' | \
    rg -x 'TestInboxAckCustodyReceiveFanoutContract')
(cd go-mknoon && set -o pipefail && \
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -run '^TestInboxAckCustody(MixedRelayAndProof|ReceiveFanout)Contract$' \
    -count=1 -v | rg '^--- PASS: TestInboxAckCustody' | \
    awk 'END { exit NR == 2 ? 0 : 1 }')
(cd go-mknoon && \
  GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -list '^TestDispatchInboxAckCustodyContract$' | \
    rg -x 'TestDispatchInboxAckCustodyContract')
(cd go-mknoon && set -o pipefail && \
  GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -run '^TestDispatchInboxAckCustodyContract$' \
    -count=1 -v | rg '^--- PASS: TestDispatchInboxAckCustodyContract')

# Full affected native packages and actual libp2p framing against synthetic handlers.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1)
(cd go-mknoon && \
  GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration \
    -list '^TestAckCustodyMixedVersionMatrix$' | \
    rg -x 'TestAckCustodyMixedVersionMatrix')
(cd go-mknoon && set -o pipefail && \
  GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration \
    -run '^TestAckCustodyMixedVersionMatrix$' -count=1 -v | \
    rg '^--- PASS: TestAckCustodyMixedVersionMatrix')

# Focused Dart proof; expect all named files green.
flutter test \
  test/core/bridge/p2p_bridge_client_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_reaction_use_case_test.dart \
  test/features/conversation/application/remove_reaction_use_case_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  test/features/feed/presentation/screens/feed_focus_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart

# Rollout/docs/metric contract and curated/family registration.
bash scripts/test/relay_ack_custody_rollout_contract_test.sh
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 2

# Android-first native closure; no phone or iOS harness is required.
bash scripts/ensure_go_android_bindings.sh
./scripts/verify_gomobile_bindings.sh android
bash scripts/test/go_binding_staleness_contract_test.sh

# Hygiene; expect zero analyzer issues/new whitespace errors.
bash -n scripts/run_test_gates.sh scripts/test/relay_ack_custody_rollout_contract_test.sh
jq empty go-relay-server/grafana-relay-dashboard.json
dart format --output=none --set-exit-if-changed lib test
find go-relay-server go-mknoon -type f -name '*.go' -print0 | \
  xargs -0 gofmt -l | awk 'NF { bad=1; print } END { exit bad }'
flutter analyze
git diff --check

# Refresh the app-owned graph once after the coherent change.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Device/Relay Proof Profile

- Profile: hermetic multi-handler + cross-process shared Redis + Android binding build.
- Boundary being proven: actual libp2p framing/action negotiation, store selection, and all-peer receive/ACK across synthetic old/disabled/new handlers with shared or disjoint state; production Redis non-destructive capacity semantics; shared Redis state across relay-process handoff; baseline legacy namespace isolation; bridge-to-Go behavior present in the Android artifact. Production handler/storage behavior is proved separately in TC-344-01..05.
- Live availability check: no mobile target is needed. Do not run or block on `flutter devices`, `adb`, or `simctl` for this plan. The Android SDK/NDK is resolved by `scripts/ensure_go_android_bindings.sh`.
- Required setup: loopback libp2p hosts, miniredis, helper subprocesses, Go 1.25, Android SDK/NDK. No Redis-server restart, frozen relay artifact, external relay, credentials, Firebase, phones, simulators, or manual taps.
- Two-peer default: N/A — no mobile two-peer behavior or OS-notification claim; the actual peers are in-process libp2p hosts.
- Closure role: required for Plan 344 code closure and a default-off deployable binary; insufficient for production admission, rollback authorization, or end-user notification presentation.
- `FLUTTER_DEVICE_ID`: N/A — host-native proof only.
- Registration: relay tests use `TestRelayNotificationClosure_`; `run_ack_custody_go_gate` owns node/bridge/tagged integration/shell proofs in `1to1` and `all`; Dart files are already pinned/AUTO; Android binding is an exact acceptance command.
- Discovery: `run_ack_custody_go_gate` must mechanically find every tagged Redis, node, bridge, and mixed-handler test before execution; the explicit TC-344-05/11 `-list` commands must each emit exactly the requested parent.
- Closure command: the TC-344-05/11 commands plus Android ensure/verify exit 0, emit a non-skipped parent PASS, and assert protected state survives until new ACK/expiry.
- Deferred device work: the GAP-N01/N02/N03 wave later runs the real-relay background/presentation campaign on one discovered USB Android plus one discovered Android emulator. Consolidated iOS runtime/APNs/NSE evidence remains GAP-N12.

## Execution Interpretation And Done Criteria

- Expected RED: TC-344-01 receives `ERROR: Unknown action` for `store_custody_v1` on HEAD, proving the new contract is absent while the legacy full-inbox sentinel remains green.
- Green sentinel: `TestStatusValueContract_FullInboxStoreStaysOK` plus old-client request/response tests remain byte/semantically unchanged.
- Pre-existing dirty tree / known failure: none at planning baseline; `git status --short` was empty at `6bab4c485dd4d13887392915abaaaabf85ea4b21`.
- Environment blocker: missing Android SDK/NDK blocks only TC-344-12 and is an environment blocker; unavailable phones/iPhones are N/A by project policy. Hermetic Go/Redis tests must not skip.
- Scope drift: any DB migration, new platform method, legacy status change, protected row in `inbox:*`, non-atomic protected/shadow acceptance, recipient registry, live deployment, or non-v108/v109 protected caller blocks completion and requires re-review.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Exact legacy protocol/overflow/push/receive preservation sentinels pass.
- [x] Harness registration is implemented and dry-run/list verified.
- [x] Redis/test-backend concurrency, relay-process handoff, baseline namespace, and framed mixed-handler proofs pass without skip.
- [x] DB v108/v109 callers retire only on exact protected proof; no bool/generic bypass remains.
- [x] Admission is default-off, Redis-only when enabled, and flag-off still drains.
- [x] Android gomobile binding rebuild/verification passes; no iOS runtime claim is made.
- [x] Curated `1to1`/`feed`, `core-host-all`, the complete stable `feature-host-all` family, analyzer, changed-file formatting, and diff hygiene pass.
- [ ] The exact `feature-host-all --batch-flutter --concurrency 2` execution is green. Two attempts exposed 10 and then 7 different early-observation failures only in unchanged `group_conversation_wired_test.dart`, followed by Flutter-runner cleanup errors. That file passed 231/231 alone, its faithful three-file neighborhood passed 385/385 at concurrency 2, and the full 839-path family passed 8,904 tests at concurrency 1. A global timing-helper change was tested, found to alter GIRD-005 transient semantics, and fully reverted.
- [ ] The repository-wide `dart format --output=none --set-exit-if-changed lib test` sentinel is green under the current SDK. It reports 506 pre-existing unchanged files; all 40 Dart files changed by Plan 344 report `0 changed`.
- [x] No full per-plan `host-all` and no production deployment occurred.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction$' -count=1)`.
- Preservation command: `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run 'TestStatusValueContract_FullInboxStoreStaysOK|TestProtocolIDContract_Frozen|TestResponseKeyContract_Frozen|TestMemoryInbox_StoreAtCapEvictsOldestReturnsStored|TestRedisInbox_StoreAtCapEvictsOldestReturnsStored' -count=1)`.
- Manual registration: add `run_ack_custody_go_gate` to `scripts/run_test_gates.sh` and call it from `1to1` and `all`; retain relay closure prefix; verify tagged tests with `-list`; no `classify_path` or device scenario.
- Migration: none; DB remains v109 and current SQLCipher staging schema is reused.
- Boundary closure: hermetic actual libp2p framing + production Redis/miniredis relay-process handoff + Android binding build. No production relay binary and no mobile/iOS device.
- Unresolved evidence: production/staging deployment, actual Redis persistence restart/restore, pinned rollback-artifact behavior, live provenance receipt, operational thresholds, real-relay Android presentation wave, and consolidated iOS closure are intentionally outside implementation authorization.

## Reviewer Findings

Initial verdict: **plan-fixes-required**. Final independent boundary recheck: **ready**. Plan classification remained a bounded GAP-N01 relay/client modification; core bet **confirmed**; disposition **apply-plan-fixes**. Independent reviewers made no file edits.

1. **[blocker, resolved] Protected-first pagination made the four-page/no-starvation claim false.** `fitRetrievePendingResponse` can trim below the requested 50 rows at the 128 KiB frame ceiling, while Dart stops each invocation after ten pages. TC-344-04 now uses stable global FIFO, the existing fitter, large-envelope fixtures, ACKed prefix progress, and later lifecycle drains; no cursor or page-limit increase was added.
2. **[blocker, resolved] Same-page coalescing did not prove old-receiver-to-upgraded convergence.** An old receiver can consume/ACK the shadow and delete local staging while the protected row remains. TC-344-09 now persists that temporal transition for text and reaction ADD/REMOVE and requires one canonical mutation, unread transition, and notification effect before protected ACK.
3. **[material, resolved] Generic typed/boolean success could still bypass strict custody.** The reviewed plan adds exact `ackOrExpiryAccepted` ownership, pins immediate/drain/failed retry/feed/bootstrap routes, names ADD and REMOVE tests, and keeps `verifyInboxCustody` plus non-v108/v109 callers legacy. An unproven `stored` is normalized to failed on strict paths.
4. **[material, resolved] The proposed bridge recorder was not injectable.** `go-mknoon/bridge` owns a concrete singleton. TC-344-07 now permits only a pure unexported dispatch helper with injected legacy/strict functions after singleton resolution; no global hook or platform method is introduced.
5. **[material, resolved] Production-relay, Redis-restart, old-binary, and push claims were overstated.** TC-344-11 proves real libp2p framing against synthetic handlers, TC-344-01..05 own production server semantics, miniredis proves relay-process handoff only, and baseline source proves namespace isolation only. Actual Redis persistence/HA and pinned rollback artifact behavior are S2 ops receipts. Push is no-duplicate/at-most-one live-process launch, not durable exactly-once delivery.
6. **[material, resolved] Promotion, conflict, expiry, and eligibility had unpinned races and exclusions.** TC-344-01..03 now cover expired legacy rows, original-expiry preservation, exact sender/bytes coalescing, last-slot and same-key conflicts, atomic known-abort versus ambiguous post-EXEC outcomes, and exact `custodyKind` structural eligibility. Identity conflict/ineligibility is terminal rather than selectable around.
7. **[blocker, resolved] First-success receive/ACK could hide disjoint mixed-pool rows.** `[upgraded empty relay, old relay with a legacy row]` previously stopped at the valid empty result. TC-344-06/11 now requires per-relay new/legacy negotiation, bounded exact union, complete-scan global emptiness, all-peer best-effort ACK, and retryable partial failure without a relay-source schema or new bridge command.
8. **[material, resolved] Wire errors and compatibility fallback were underspecified.** The plan now freezes exact new success/full/disabled/conflict/ineligible shapes, the old `Unknown action` form, malformed proof behavior, terminal versus retryable store outcomes, no legacy store fallback, and per-relay receive/ACK fallback without treating one peer as pool authority.
9. **[gate fix, resolved] Several focused commands could pass vacuously or omit real callers.** Every new untagged relay parent plus TC-344-05/06/07/11 requires literal discovery and a non-skipped parent PASS; focused Dart includes retry, feed, and production bootstrap; `feed` is a curated gate; shell/JSON/gofmt hygiene is executable. Full `host-all` remains correctly deferred to wave and release cadence.
10. **[scope cut, resolved] Protected production memory backends and broader rollout machinery were unnecessary.** Production custody is Redis-only with a narrow deterministic test backend. Receive/ACK fanout reuses configured peers and existing lifecycle retries. No DB migration, worker, push outbox, cursor, capability registry, dynamic flag service, new platform API, mobile-device campaign, or iOS runtime harness belongs to Plan 344.

## Arbiter Decision

Final verdict: **ready**. Plan classification: reviewed implementation-ready GAP-N01 non-destructive-capacity/mixed-version slice; core bet **confirmed**. Disposition: **execute**, producing a default-off deployable binary only—no live admission or standalone release claim.

- L1 evidence truth: clear; legacy eviction, strict-caller bypasses, frame trimming, concrete bridge ownership, and Redis/default-memory boundaries are source-confirmed.
- L2 causality: clear after exact at-cap, race, promotion/expiry, wire-table, oversized pagination, disjoint mixed-relay fanout, temporal upgrade replay, and strict-retirement tests.
- L3 bypass/scope: clear after every v108/v109 owner, feed/bootstrap composition, structural eligibility, terminal conflict, named legacy siblings, and limited fake boundaries were pinned.
- L4 gates: clear; every new Go parent is discovery/non-skip checked, focused Dart files and `1to1`/`feed` plus justified core/feature families are explicit, Android binding is host-built, and per-plan full `host-all` is excluded.
- L5 boundary/reversibility: clear for Redis-only default-off code, isolated keys, admission kill switch with read/ACK continuity, no historical backfill, Android-first closure, and deferred iOS. Real Redis restart/restore, old-artifact rollback, deployment, traffic thresholds, and presentation remain named ops/wave evidence.
- Evergreen sweep: state transitions, lifecycle re-entry, derived side effects, destructive legacy reads, sibling callers, frame limits, cross-process ownership, and mixed-version sequences are directly covered. No product decision blocks implementation and no speculative architecture is required.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-07 16:12 CEST | RED / contract extraction | `go-relay-server/protocol_contract_test.go`; rollout source-contract scaffold | `GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction$' -count=1` -> exit 1 | Relay returned frozen `Unknown action: store_custody_v1`; expected `rejected_full`/`INBOX_FULL`. Legacy state was seeded before the request. `scripts/test/relay_ack_custody_rollout_contract_test.sh` independently failed on the absent protected metric surface. | Planned runtime RED established before production edits; baseline HEAD `6bab4c485dd4d13887392915abaaaabf85ea4b21`; pre-existing dirty files were the new Plan 344 document and its index entry. | Implement relay, native bridge/node, and Dart strict-custody seams; turn each named proof green. |
| 2026-08-07 18:55 CEST | GREEN / relay and mixed-version implementation | Protected Redis lane, relay actions/metrics/bootstrap/docs, Go node/bridge, tagged process and framed-handler fixtures | Six literal relay parents and preservation sentinels PASS; full `go-relay-server` PASS; full `go-mknoon ./node ./bridge` PASS; Redis process handoff and `TestAckCustodyMixedVersionMatrix` PASS without skip; targeted race/vet and rollout shell PASS | Atomic protected+shadow commit, duplicate-before-cap, conflict/full/expiry/promotion, default-off Redis-only admission, per-relay receive/ACK negotiation, and exact bridge proof are closed. Representative production mutation re-established RED and was restored before final GREEN. | No relay deploy, real Redis restart/restore, or pinned old-artifact claim was made. | Keep production admission off pending the named S2 ops receipts. |
| 2026-08-07 18:55 CEST | GREEN / Dart ownership and regression gates | v108/v109 send/drain/retry/feed/bootstrap owners; receiver temporal replay; strict test adapters | Focused 12-file suite PASS (494 tests); curated `1to1` PASS (2,919 Flutter tests plus registered Go/shell proofs); `feed` PASS (323); `core-host-all --concurrency 2` PASS (401 paths / 3,170 tests) | Every v108/v109 retirement site requires exact `ack_or_expiry_v1`; old-receiver -> upgraded protected redelivery converges once for encrypted text and reaction ADD/REMOVE; stale fakes discovered by the wider gates were updated to model the exact contract rather than weaken production checks. | No bool/generic receipt bypass remains in the scoped owners. | Complete the feature family and host hygiene. |
| 2026-08-07 18:55 CEST | GREEN with harness caveat / feature family | All 839 `test/features/**` paths; exact ACK-gated preservation fixture | Corrected final tree: `feature-host-all --batch-flutter --concurrency 1` PASS (8,904 tests, one existing skip); `inbox_custody_verify_test.dart` PASS (4). Two exact concurrency-2 attempts failed in the unchanged group conversation fixture with 10 then 7 non-overlapping pending-state observations; the file alone PASS (231) and its three-file neighborhood PASS (385) at concurrency 2. | The deterministic stale P2P fake was corrected to echo the requested strict retrieve/ACK proof. No broad group timing patch was retained because the experiment regressed GIRD-005 semantics. | Exact concurrency-2 harness receipt remains open; the complete feature behavior is green in the stable serial shape. | Harden those unrelated group scenarios later with per-scenario causal completion signals, not shared sleeps/yields. |
| 2026-08-07 18:55 CEST | Android / hygiene / graph closure | Android AAR, changed Dart/Go/shell/JSON, `graphify-arch` | Android ensure (via `bash`), export verification, and binding staleness PASS; `flutter analyze` reports no issues; 40 changed Dart files format with 0 changes; shell syntax, dashboard JSON, Go formatting, and `git diff --check` PASS; Graphify incremental refresh PASS at fingerprint `fa8e958259e251a5` | Repository-wide Dart format sentinel separately reports 506 pre-existing unchanged files under the current SDK. Architecture graph refreshed exactly once after the coherent app-owned change. | No full per-plan `host-all`, device/iOS leg, production deployment, or activation occurred. | Handoff the default-off code and the two explicit harness/baseline caveats. |
