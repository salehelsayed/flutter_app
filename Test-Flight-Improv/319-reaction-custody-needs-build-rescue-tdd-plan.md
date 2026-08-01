# 319 - Reaction Custody Needs-Build Rescue (F3): Stage-Throw Abandonment, All Three Shapes, Both Lanes

Status: execution-ready (v2, /tdd-review applied 2026-08-01 — 3-worker audit `wf_fc5b2655-1c3`, verdict plan-fixes-required with 2 blockers on the migration/rollback story; all deltas folded in; core defect + id-policy bets CONFIRMED)
Type: Bug
Spec: free-text intent — F3 deferred from plan 315 with a named owner; REMOVE-lane twin folded in
Classification: implementation-ready
Closure tier: host (Dart feature tier + migration host tier; relay untouched — the conflict-mapping consumes an EXISTING relay error string; no deploy)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-01 (grounding) | Evidence Collector (10-agent verify→refute `wf_5c74a876-7b1` + firsthand seam read) | send/remove reaction use cases (full), group_offline_replay_envelope.dart, outbox repo+helpers+054 migration, retriers, relay inbox.go custody keying, receiver ingress dedupe | C1/C3/C4 confirmed; **C2-as-stated REFUTED — fresh-id rebuild double-banners (live publish already ran; every notification surface dedupes by transitionId) and custody identity is the extension TransitionID (inbox.go:1165-1174), not envelope messageId** | corrected design |
| 2026-08-01 (design) | Planner | 054 schema, retryable query helpers:128-133, _attemptReactionInboxStore :509-571 | **needs_build-first staging with ORIGINAL-id rebuild + conflicting-messageId→stored mapping**; DB v105; REMOVE lane gains the 315 pre-check at its choke point | emit plan, /tdd-review |

## Problem And Evidence

- Behavior to improve: a group reaction (ADD or REMOVE) whose offline-replay envelope build/stage throws keeps its optimistic UI state and may even live-publish successfully, but acquires **no outbox row** — no retrier can ever rescue it, so relay custody, offline replay, and the recipient wake are permanently and silently lost. `GROUP_REACTION_SEND_QUEUED` then lies `replayStatus: 'pending'` (:254-263) and the result can report `success`.
- Impact: silent custody loss for reactions on ordinary runtime failures (bridge NOT_INITIALIZED/GROUP_ERROR → `BridgeCommandException` from `callGroupEncrypt`, `StateError 'Missing group replay key'` (envelope:1223-1226 — the reaction path passes no keyInfo), roster DB errors, sign StateErrors, the 315 subset-assert). Offline recipients never see these reactions; online recipients got the live banner but no durable custody exists for anyone else.
- Confirmed defect — **three silent-loss shapes per lane** (survived the refute pass, HEAD `71feba8a5` lineage; last seam commit `d6fa0a778`/315 — nothing in 315-318 fixed any of them):
  1. **Build-throw abandonment**: `_stageReactionInboxStore`'s single try (send:318-349) covers recipient resolution AND `buildGroupOfflineReplayInboxRetryPayload`; the catch (send:350-357) emits `GROUP_REACTION_OUTBOX_STAGE_FAILED` and returns BEFORE the entry is constructed (:359) or saved (:374). The caller persists the local reaction anyway (:216), live-publishes (:224), and reports success. Six-plus enumerated production-reachable throw sites inside the try.
  2. **saveEntry-throw**: payload built, `saveEntry` throws (:373-382) → one unawaited store attempt with `staged:false` (:384-392) — a store failure leaves nothing durable.
  3. **staged-true-no-row (new finding)**: `dbUpsertGroupReactionReplayOutboxEntry` ignores the boolean from `dbInsertOrdinaryGroupOwnedRow` (group_reaction_replay_outbox_db_helpers.dart:48-53); the group-parent write guard silently inserts 0 rows for a self-removed group parent (group_parent_write_guard.dart:58-67) → `staged=true` with no row.
  REMOVE lane (remove_group_reaction_use_case.dart): shape 1 identically (:287-294 returns before :296/:311; tombstone still lands :174-178; `REMOVE_QUEUED` lies `'pending'` :223; the wired comment at group_conversation_wired.dart:7422-7425 falsely asserts "durably staged"), **plus GAP 2: `_attemptRemoveReactionInboxStore` (:351-393) has NO unroutable pre-check** — the shape 315 fixed in send survives in remove, and remove's exactRetry (:147-156) replays a persisted possibly-empty payload with `staged:true`, false-storing via the Go silent no-op (group_inbox.go:190-192, config-loaded arm; the un-joined arm flows the empty list to the relay — both shapes covered by the pre-check).
- Rescue-blocking schema fact: the 054 outbox table requires `inbox_retry_payload TEXT NOT NULL` with `delivery_status CHECK(pending,failed,stored)` — a needs-build row is unrepresentable; the retryable query selects only `pending,failed` (helpers:128-133).
- Rebuild feasibility: every row-identity field exists BEFORE the throwing steps — transitionId (row PK) minted at send:169-173 (reused from `latestTransition` on exactRetry), the payload identity (groupId/messageId/sender/emoji/action) at :175-183, the stage call at :200. The durable `message_reactions` fact drops the transitionId (`toMessageReaction`, group_reaction_payload.dart:105-114) — which is exactly why the needs_build ROW must carry it.
- **Corrected id policy (C2 refutation + C4, the plan's core design):**
  - **Reuse the ORIGINAL transitionId and the deterministic reaction id on rebuild.** Fresh ids are wrong: F3 never stops the live publish, so recipients are routinely already notified, and every notification surface dedupes by `boundedReactionEventIdentity(transitionId)` (in-app banner, wake-push handler, per-event `apns-collapse-id` since v1.7.4; Android non-collapsible since 309) — a fresh transitionId double-banners with nothing to absorb it. The deterministic reaction id is also load-bearing for receiver idempotency (`UNIQUE(message_id,sender_peer_id)` upsert) and the pending-buffer PK.
  - **Relay custody identity for a valid reaction envelope is the extension TransitionID** (inbox.go:1165-1170, before the messageId fallback :1172-1174). Same-transitionId rebuild in the abandonment case is fresh to the relay → stores + wakes once; already-live-notified clients dedupe the push by event identity → no double banner.
  - **Lost-ack / partial shapes**: rebuilt bytes can never equal the originals (fresh nonce), so a same-id re-store where bytes DID land hard-errors `conflicting group inbox messageId` (backend_redis.go:626-637, compared only when the extracted id matches). **Map that error client-side to custody-already-exists → mark the row `stored`** — safe because the deterministic id embeds the sender; without the mapping such rows fail forever until relay TTL.
  - **Always attach the notification extension on rebuild** — else custody keying silently degrades to the deterministic messageId and a second rebuild collides with the first (C4 residual 3).
- Accepted attention-side cost (documented): none in the common paths under the original-id policy; the only residual double-wake window is a true lost-ack where the FIRST store's wake fired while no client observed the event — bounded and correct-direction.
- Existing coverage: 315's rows — the unroutable pre-check tests (send lane), EK004 red-on-dropped-shape, retirement tests (`retry:372/:383` deleteEntry for unroutable rows), exactRetry probes (send:160-167). The retrier reaction leg (`_retryGroupReactionReplayCandidate` retry:363-453) has CAS-guard and exact-completion tests. **No test exercises any of the three abandonment shapes, the remove pre-check absence, the write-guard boolean, or a rebuild.**
- Refuted findings (do NOT re-introduce): **(R1) fresh-transitionId rebuild** (double-banner; unretirable conflict rows in lost-ack). **(R2) fresh/freshened deterministic reaction id** (breaks receiver idempotency + buffer PK). **(R3) missing-row reconciliation via re-driving `sendGroupReaction`** (re-mints ids deterministically BUT re-runs the full send incl. live publish → double live banner; and cannot represent build-context) — the needs_build row is the reconciliation. **(R4) omitting the extension on rebuild.**
- Unresolved findings: none material — every claim reached confirmed/refuted with line evidence.
- Affected production / test / gate files: send_group_reaction_use_case.dart, remove_group_reaction_use_case.dart, group_reaction_replay_outbox_entry.dart (+repo interface/impl + db helpers), NEW migration `105_reaction_outbox_needs_build.dart`, retry_failed_group_inbox_stores_use_case.dart (rebuild leg + conflict mapping + needs_build in the query), group_offline_replay_envelope.dart untouched; tests: send/remove use-case tests, outbox repo/helpers tests, retry tests, NEW migration test; gates: none new (files already curated per 315).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `923f2be5c3095000` → refreshed post-309-re-land this session; refined query `confidence=anchored`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "_attemptReactionInboxStore send_group_reaction_use_case.dart reaction outbox stage exactRetry" --profile tdd --budget 700`.
- Anchors: `_attemptReactionInboxStore` → send_group_reaction_use_case.dart:509; `exactRetry` → remove_group_reaction_use_case.dart:124.
- Graph gaps that required raw source search: relay custody keying (Go), 054 schema, write-guard behavior, receiver dedupe keys — all raw-source (workflow agents).
- Reuse rule: anchors are search starting points; conclusions carry current-source evidence.

## Scope Contract And Guard

**In scope:**
- **DB v105** (`test/core/database/migrations/105_reaction_outbox_needs_build_test.dart` + live migration), **review-pinned representation: SENTINEL-EMPTY payload, column stays NOT NULL** — `''` payload is legal ONLY with the new `needs_build` status (CHECK ties emptiness to the status); `delivery_status` CHECK widens with `needs_build`. Rationale (review blocker): old builds read the table through NON-status-filtered queries (`getLatestEntryForTarget` helpers:91-110 — hit on EVERY reaction send/remove) and `fromMap` casts the payload `as String` (entry:42) — a NULL would crash a rolled-back build; `''` parses fine and at worst degrades the row to a failed, non-crashing retry loop the NEW build's rebuild predicate also catches (keys on status OR empty payload). Table-rebuild migration (create-copy-swap) **explicitly copying rowid** (`INSERT INTO new (rowid, <cols>) SELECT rowid, <cols> FROM old` — two production readers tiebreak `rowid DESC`, helpers:105 + e2e probe:314) and recreating BOTH indexes. **Registration ripple (review add — was unplanned): `production_migration_registry.dart` gains the 105 entry in BOTH `productionCreateMigrations` and `productionUpgradeMigrations` (~:601/:1088 lists), `app_database_version.dart` bumps `currentIdentityDatabaseVersion` 104→105, and the seven pinned-assertion chain tests (100-104 migration tests, `full_migration_chain_test`, `migration_database_active_importer_test`) get their expected-version updates — each named in E1.**
- **needs_build lifecycle across ALL consumers (review add)**: the four live cleanup sweeps with hardcoded `delivery_status IN ('pending','failed')` gain `'needs_build'` (group_media_deletion_journal_db_helpers.dart:209-213, group_exit_intents_db_helpers.dart:604-609, self_removed_group cleanup, + the fourth site the grep names — they mean "all still-deliverable rows"; 102's historical predicate untouched); the Move pending-work manifest builder's `_isGroupReactionReplayStatus` admits `needs_build` with payload-optional handling (else account migration silently drops rescued custody); the in-app E2E probe (group_reaction_e2e_probe.dart:308-321) gains a status filter so its `as String` hard-cast never meets `''`-sentinel rows.
- **Stage restructure, both lanes**: persist a `needs_build` row (all identity fields, NULL payload) BEFORE the throwing build steps; on successful build, UPDATE the row to `pending` with the payload (an update failure leaves `needs_build` — shape 2 fixed structurally); the old post-build insert disappears.
- **Write-guard honesty**: `dbUpsertGroupReactionReplayOutboxEntry` honors the insert boolean; a guarded 0-row write returns false → the stage emits a DISTINCT event (`GROUP_REACTION_OUTBOX_STAGE_SKIPPED_PARENT_GONE`) — a self-removed group legitimately stages nothing (leaving-group semantics), now observable instead of `staged=true` fiction.
- **Retrier rebuild leg**: the retryable query gains `needs_build` (and treats empty-payload rows of any status as rebuildable — the rollback round-trip shape); `_retryGroupReactionReplayCandidate` gains a rebuild branch — **recipient resolution is REBUILD-TIME-BY-DESIGN** (fresh roster = fresh ACL truth; recipientSetHash + the extension replay-subset invariant recompute together) using the send lane's resolver (its removed-author-snapshot fallback included), `buildGroupOfflineReplayInboxRetryPayload` with the row's ORIGINAL transitionId and deterministic reaction id, **rebuilt plaintext eventId = row PK and timestamp = row.created_at** (review add: a rebuild-time timestamp would defeat the receiver's tombstone stale-guard — an abandoned ADD rebuilt after a REMOVE must not out-time the tombstone; created_at is the closest surviving proxy for the authored timestamp), notification extension ALWAYS attached; sender identity/keys from `identityRepo.loadIdentity()`, device identity via `groupRepo.getMember(...).firstActiveDeviceForSigningKey(identity.publicKey, allowLegacyFallback: true)` (the send lane's own selection, send:107-110), ADD target-author from `msgRepo.getMessage(row.messageId)` (fail-soft to `needs_build` when the target is gone — folds into TC-07); promote via a NAMED repo surface **`attachBuiltPayload(reactionId, payload)`** (atomic needs_build→pending; TC-03's unambiguous failure-injection target), then the normal store; a rebuild failure re-marks `needs_build` with `last_error`. **Private-symbol exports (review add)**: `_deterministicAddReactionId` (send:276-291), `_deterministicRemoveReactionId` (remove:40-53), and the send-lane recipient resolver move to a shared library so the retriever can reuse them verbatim.
- **Conflict mapping**: in the store-failure classification (both `_attemptReactionInboxStore` and the retrier completion), the relay error is matched via a **single shared const `groupInboxCustodyConflictLiteral = 'conflicting group inbox messageId'`** (review-pinned matcher shape: `errorMessage.contains(<const>)`, defined once in lib/; the fake-bridge fixtures import the SAME const so matcher and reality cannot drift) → row `stored` + distinct flow event `GROUP_REACTION_CUSTODY_ALREADY_PRESENT`. A **negative leg** feeds a different conflict-flavored error (`'conflicting something else'`) and asserts it stays `failed` — kills over-broad matchers.
- **exactRetry probe amendment (review-corrected — the v1 "probes untouched" preservation was REFUTED)**: `getLatestEntryForTarget` has NO status filter (helpers:91-110) and the probes (send:160-167, remove:124-127) check neither status nor payload presence, so a needs_build row WOULD be selected and its empty payload replayed. Both probes gain a payload-present condition; **when the latest row for the target matches (action, +emoji for ADD) and is `needs_build`, the stage REUSES its `reactionId` as the transitionId** instead of minting fresh — the PK-keyed upsert (ConflictAlgorithm.replace, helpers:52) then updates the row in place; without the reuse, a re-tap mints a sibling row and orphans the needs_build one.
- **REMOVE-lane pre-check**: port 315's unroutable-empty-recipients pre-check into `_attemptRemoveReactionInboxStore` (the choke point — covers stage AND exactRetry call sites), with the send lane's exact semantics (row `failed` + `custody_unroutable_empty_recipients`; retirement then deletes).
- Truthful telemetry: `SEND_QUEUED`/`REMOVE_QUEUED` report the ACTUAL replay status (`needs_build`/`pending`/`stage_skipped`), never an unconditional `'pending'`.

**Must preserve:**
- exactRetry OUTCOMES for pending/failed/stored rows both lanes (persisted-payload replay; behavioral sentinels) — the probe PREDICATES gain the payload-present/needs_build-reuse conditions above (v1's "predicates untouched" wording was review-refuted).
- 315's send-lane pre-check + retirement + EK004 red-shape → existing tests untouched.
- Deterministic reaction id derivation (send:143-148/:276-291) and transitionId minting (:169-173, factory format) → sentinels; the needs_build row PK stays the transitionId.
- Envelope builder unchanged (`buildGroupOfflineReplayInboxRetryPayload` signature/behavior).
- Retrier ordering (message rows first, reaction rows in leftover slots, retry:122-128) and CAS guards.
- Local optimistic persist + live publish ordering (INV-R1 comment :185-188: stage precedes both).

**Hard `Do not`:**
- Do not touch go-relay-server (the conflict string is an EXISTING error; grep-gate pins it) — no deploy.
- Do not re-introduce R1-R4 (fresh ids, send re-drive reconciliation, extension-less rebuild).
- Do not change receiver-side dedupe/upsert keys or the pending-buffer PK.
- Do not widen the retrier's slot budget or ordering.

**Deferred / accepted difference:**
- The un-joined-group empty-recipient relay-path arm (C3 residual a): the pre-check makes it moot client-side (empty sets never reach the store); the Go-side shape stays unverified-by-design. N/A-with-note.
- True lost-ack double-wake residual (bounded, correct-direction) — documented above; no sentinel possible client-side.
- Legitimate no-victim empty sets (solo group / all-revoked) follow the 315 template semantics (unroutable → retire) — already the send lane's accepted behavior, now symmetric.
- Rollback: the migration is additive-permissive (NULLABLE + wider CHECK); a REVERTED build reading a `needs_build` row would fail its CHECK on write... **it does not**: old builds never write `needs_build` and read via status-filtered queries (`pending,failed`) that simply skip it; the row sits inert until the new build returns or relay TTL passes. One-way risk: none (no data loss either direction). `## Rollback` section below.

**Dependencies:** none external; migration numbering `DB v105` (live files 100_-104_; 054 is the historical outbox-creation migration in the legacy range).

## User-Owned Decisions
None open — the id policy and conflict mapping are evidence-forced (R1-R4); the write-guard skip semantics follow existing leaving-group behavior; deploys N/A (client-only).

## Test Contract

Dart rows in the files noted (all already feature-glob + GROUP_TESTS-curated per 315 except the NEW migration test, AUTO under `test/core/**`).

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-319-01 | **DB v105** (sentinel-empty representation): `''` payload legal only with `needs_build`; CHECK widened; rows preserved **incl. rowid** (tiebreak readers) and BOTH indexes recreated; `user_version` preserved; run-twice idempotent; **registry (both lists) + version-constant 104→105 wired; the seven pinned chain tests updated** | `105_reaction_outbox_needs_build_test.dart::migration widens status and preserves rows, rowid, and indexes` + updated chain tests | migration host / ffi + PRAGMA table_info + `index_list/index_info` + rowid before/after + run-twice | causal RED (no migration; chain tests pin 104) → all hold | drop the rowid copy → red; drop one index recreation → red | `flutter test <exact path>`; AUTO (`test/core/**`) + **add to GROUP_TESTS (102-precedent, grep-verify)** + completeness |
| TC-319-02 | **HEADLINE (send, shape 1)**: a build-throw leaves a durable `needs_build` row (ORIGINAL transitionId PK, `''` payload); `SEND_QUEUED` truthful; **plus the review-added ordering leg: a `getMembers` throw (the FIRST throwing step, upstream of the encrypt) ALSO leaves the row** — pins insert-before-first-throwing-step, killing mid-try-insert implementations | same file `::build failure stages a rescuable needs-build row` + `::roster failure stages a rescuable needs-build row` (per lane) | unit/host — fake bridge `group:encrypt` throw; throwing-getMembers repo fake | causal RED (HEAD: catch returns rowless in both fixtures) → row exists, status `needs_build`, payload `''`, PK == minted transitionId; QUEUED truthful; result stays `success` when publish succeeds (enum semantics unchanged — the durable row carries the truth) | restore the return-before-insert catch → both red; move the insert after recipient resolution → roster leg red | direct `flutter test` + GROUP_TESTS (existing files) |
| TC-319-03 | Shape 2 (send): a `saveEntry`/UPDATE failure after a successful build leaves the `needs_build` row (never nothing) | same file `::payload update failure leaves the needs-build row rescuable` — repo fake failing the UPDATE only | unit/host | causal RED (HEAD: nothing durable) → `needs_build` row persists | make the stage insert-after-build again → red | same |
| TC-319-04 | Shape 3 (send): the write-guard 0-row insert is honored — distinct `…STAGE_SKIPPED_PARENT_GONE` event, `staged=false`, no fictional row claims | outbox helpers test `::guarded zero-row upsert reports false` + use-case test `::self-removed parent skips staging observably` | unit/host — sqflite_common_ffi with the parent guard geometry | causal RED (HEAD: helper ignores the bool; staged=true fiction) → false surfaced + distinct event | swallow the bool again → red | AUTO + GROUP_TESTS (existing files) |
| TC-319-05 | **Retrier rebuild**: a `needs_build` row is selected, rebuilt with ORIGINAL ids + extension, promoted via `attachBuiltPayload`, stored, marked `stored`; **four identity legs on the ONE captured payload (review-extended)**: extension transitionId == row PK; envelope messageId == deterministic reaction id; **decoded plaintext eventId == row PK AND timestamp == row.created_at** (tombstone stale-guard protection); **recipients == REBUILD-time roster** (fixture mutates the roster between stage and retry — rebuild-time resolution is by-design) | `retry_failed_group_inbox_stores_use_case_test.dart::needs-build row is rebuilt with original identity and stored` | unit/host — fake bridge capturing store payload + encrypt plaintext | causal RED (HEAD: query skips it; no branch) → all four legs hold; row `stored` | mint a fresh transitionId → red; mint a now() timestamp → red | same |
| TC-319-06 | **Conflict mapping** via the shared const (`groupInboxCustodyConflictLiteral`) at both completion sites; **negative leg (review add): a different conflict-flavored error (`'conflicting something else'`) stays `failed`** — kills over-broad matchers | same file `::custody conflict marks stored` + `::unrelated conflict errors stay failed` + send twin | unit/host — fake bridge errors built FROM the shared const (drift-proof) | causal RED (HEAD: any error → failed) → exact-literal → `stored` + event; other → `failed` | broaden the matcher to `contains('conflict')` → negative leg red | same |
| TC-319-07 | Rebuild failure re-marks `needs_build` with `last_error` (retryable forever, observable) — never `failed`-retired, never lost | retry test `::rebuild failure keeps the row rescuable` | unit/host — builder throw during rebuild | causal RED (no branch exists) → status `needs_build`, last_error set | mark rebuild failures `failed` → red | same |
| TC-319-08 | **REMOVE shape 1**: build-throw stages a `needs_build` remove row; `REMOVE_QUEUED` truthful | `remove_group_reaction_use_case_test.dart::remove build failure stages a rescuable needs-build row` | unit/host | causal RED (HEAD: catch returns rowless; QUEUED lies) → row + truthful status | restore return-before-insert → red | same |
| TC-319-09 | **REMOVE pre-check (GAP 2)**: empty-recipient remove payloads are marked `failed`/`custody_unroutable_empty_recipients` at `_attemptRemoveReactionInboxStore` — covering BOTH stage and exactRetry call sites — and the retirement deletes them | remove test `::unroutable remove custody fails loudly at the choke point` (+ exactRetry variant) | unit/host — empty-recipient persisted payload | causal RED (HEAD: no pre-check; Go silent no-op → false `stored`) → `failed` + distinct event; retirement sweeps | remove the pre-check → red | same |
| TC-319-10 | Truthful telemetry: `SEND_QUEUED`/`REMOVE_QUEUED` `replayStatus` equals the actual row status in every stage outcome (pending / needs_build / stage_skipped) | assertions folded into TC-02/03/04/08 | unit/host | causal (folded) | hardcode `'pending'` again → TC-02/08 red | same |
| TC-319-11 | exactRetry amended (review-corrected): pending/failed/stored rows keep their replay OUTCOMES (sentinels); a `needs_build` row is NOT replayed — the probe's new payload-present condition routes it to a stage that **REUSES the row's reactionId as the transitionId**, and after the re-tap the outbox holds **exactly ONE row for the target with the ORIGINAL PK** (kills the sibling-row/orphan implementation) | existing exactRetry tests + `::needs-build row is re-staged in place on retry` (per lane) | unit/host | GREEN sentinels + causal RED (HEAD probe would replay the empty payload; fresh-mint would orphan) → one row, original PK, status advanced | mint fresh on fall-through → red (row-count+PK assertion) | same |
| TC-319-12 | 315 send-lane pre-check, retirement, EK004, CAS guards, retrier ordering, TC-318-14 frozen-replay — all untouched | existing tests | unit/host | GREEN sentinels | guarded by their own existing mutations | existing gates |
| TC-319-13 | Relay conflict string is a REAL contract: grep-gate pins `conflicting group inbox messageId` in backend_redis.go + backend_memory.go; the client matcher references the same literal | acceptance grep (below) + a Dart const shared by matcher and tests | gate-level | GREEN sentinel | relay renames the string → grep red | acceptance gate |
| TC-319-14 | Migration rollback honesty (review-rewritten — the v1 leg was vacuous): the REAL old read path — the UNFILTERED latest-for-target query + `fromMap`'s `as String` — parses a `needs_build` row without crashing (sentinel `''`), and the new build's rebuild predicate also catches empty-payload rows of any status (the rollback round-trip shape) | migration test legs `::old unfiltered probe parses needs-build rows` + retry test `::empty-payload failed row is rebuilt` | migration host + unit/host | causal RED (no legs) → both hold | switch the representation to NULL → parse leg red | AUTO + GROUP_TESTS |
| TC-319-15 | needs_build lifecycle in ALL consumers (review add): the four cleanup sweeps delete `needs_build` rows on exit/self-removal/message-deletion; the Move manifest carries them (payload-optional); the E2E probe's hard-cast never meets a sentinel row | cleanup helper tests + manifest builder test + probe query grep-gate | unit/host + gate | causal RED (HEAD IN-lists exclude the status; manifest drops; probe unfiltered) → all hold | drop `needs_build` from one IN-list → red | AUTO + GROUP_TESTS (existing files) + acceptance greps |

### Test Notes
- TC-02's throwing seam: the fake bridge's `group:encrypt` throw reproduces the real `BridgeCommandException` path (envelope:133-143); the six other throw sites collapse into the same catch — one representative RED suffices, with the catch-restructure covering all (census in Risks).
- TC-05's identity assertions are the R1/R2 kill-shots: extension `transitionId == row.reactionId` (PK) AND envelope `messageId == deterministic reaction id` — assert BOTH on the captured store payload (relationship assertion, one payload).
- Rebuild sender-device resolution: identity from `identityRepo`, own roster self-row for device identity — the rebuild branch must fail-soft to `needs_build` (TC-07) when either is unavailable (e.g. mid-migration states).
- The write-guard geometry (TC-04) uses the real helpers on `sqflite_common_ffi` with a self-removed parent row — fake-fidelity for the 0-row insert is the point; do not fake the guard.

## Implementation Steps
1. `git status --short`. Write TC-319-02 FIRST (runtime RED, file compiles) → capture; then TC-01 (migration RED) and the rest.
2. E1 — migration 105 (table-rebuild copy-swap; NULLABLE payload + widened CHECK) + entry/repo/helper types (`GroupReactionReplayOutboxStatus.needsBuild`; nullable payload field).
3. E2 — send stage restructure (needs_build-first; UPDATE-to-pending on build success; guard-bool honesty + skip event; truthful QUEUED status).
4. E3 — remove stage restructure (same) + the choke-point pre-check port (both call sites).
5. E4 — retrier: query includes `needs_build`; rebuild branch (original ids, extension attached, fail-soft re-mark); conflict mapping in both completion sites; shared conflict-string const.
6. E5 — tests per contract; registration: none new except the migration test (AUTO `test/core/**` + completeness).
7. E6 — gates ladder below. Stop-if: the rebuild needs a dependency the retriever cannot reach without widening a shared signature used by many callers → stop and replan the injection, don't thread ad hoc.

## Risks And Blind Spots
- Throw-site census (re-derived): all build-path throws funnel through the ONE catch per lane (send:350, remove:287) — the restructure moves the row insert above the try, covering every site; grep-gate `GROUP_REACTION_OUTBOX_STAGE_FAILED` sites stay exactly 2 per lane (build + update legs).
- Lifecycle/derived-state: the needs_build row IS the durable derived state; TC-05/07 assert reconstruction across retrier passes; no in-memory latch.
- Sibling-surface consistency: both lanes get identical structure; the pre-check asymmetry (315's send-only) is closed by TC-09; the 1:1 reaction lane has its own outbox-less design (out of scope, unchanged — no invite of this machinery).
- Destructive-action side effects: retirement (deleteEntry) semantics unchanged and still scoped to unroutable rows — TC-12 sentinels; rebuild never deletes.
- Invariant re-verification: the new needs_build→pending→stored transitions are asserted with full row state (TC-02/05); conflict→stored asserts the terminal state + event (TC-06).
- Construction/call-site census: `saveEntry` production call sites were exactly send:374 + remove:311 (grep, workflow-verified) — both restructured; `_attemptReactionInboxStore` 3 store paths + remove's 2 covered; grep gates in acceptance.
- Build-artifact provenance: N/A (no native artifact, no deploy).
- Permission/ACL: N/A — no ACL surface; custody ACL untouched.
- Fake side-effect fidelity: TC-04 uses the REAL guard+helpers on ffi; the fake bridge's conflict error uses the shared const (TC-13) so the matcher and reality cannot drift.
- Composite/relationship: TC-05's dual-id assertion on ONE captured payload.

## Gate Cadence
- Per-plan closure: focused causal tests + sentinels + the curated `groups` lane (owns every touched Dart test file per 315) + the migration test directly. No broad sweep justified.
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/features/groups/application/send_group_reaction_use_case.dart lib/features/groups/application/remove_group_reaction_use_case.dart lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart --budget 600` → run named files directly BEFORE the lane.
- Full `host-all`: owned by the notification-reliability wave closure (after F5 + C3-plan + D4) and final release closure.
- Shared tests outside feature/core globs: none.

## Acceptance Gates  (literal — copy/paste; `flutter` = host shim; lane via host bridge)
```bash
git status --short

# Causal RED (TC-319-02 written alone first) — must FAIL: HEAD leaves the outbox empty after a build throw
flutter test test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name 'build failure stages a rescuable needs-build row'

# Migration RED then GREEN
flutter test test/core/database/migrations/105_reaction_outbox_needs_build_test.dart

# Focused GREEN (after E1-E5) — exit 0, zero failures
flutter test test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/remove_group_reaction_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart

# Conflict-string contract (TC-319-13) — expect: both backends match + the shared Dart const matches
grep -c 'conflicting group inbox messageId' go-relay-server/backend_redis.go go-relay-server/backend_memory.go
grep -rn 'conflicting group inbox messageId' lib/ | head -3

# Stage-event census — exactly 2 STAGE_FAILED emitters per lane (build + update legs) + the new skip event present
grep -c 'GROUP_REACTION_OUTBOX_STAGE_FAILED' lib/features/groups/application/send_group_reaction_use_case.dart lib/features/groups/application/remove_group_reaction_use_case.dart
grep -rn 'STAGE_SKIPPED_PARENT_GONE' lib/ | head -2

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected lib/features/groups/application/send_group_reaction_use_case.dart lib/features/groups/application/remove_group_reaction_use_case.dart lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart --budget 600

# Zero relay diffs — client-only plan
git status --short go-relay-server/ && git diff --stat go-relay-server/   # expect: both empty

# Curated lane (host-side) — exit 0
/claude-host-bin/host-run bash ./scripts/run_test_gates.sh groups

# Registration/classification — migration test is a NEW file
./scripts/run_test_gates.sh completeness-check    # expect: PASS

# Hygiene
flutter analyze
git diff --check
```
Semantic outcomes: TC-02 RED via empty-outbox assertion failure; migration file compiles standalone; GREENs zero failures; greps exactly as annotated; relay tree untouched; lane exit 0; completeness PASS; analyzer/diff clean.

## Rollback (review-rewritten — v1's story was FALSE in both directions)
- **The DB version floor is one-way by project design**: `encrypted_db_opener.dart:268` sets `onDowngrade: onDatabaseVersionChangeError` — a FULL `git revert` (which would also revert `currentIdentityDatabaseVersion` to 104) fail-closes every migrated device at open. **Rollback = revert application code ONLY while KEEPING the 105 migration + the version constant** (the v96 precedent).
- What a PRIOR-shaped build (code-reverted, schema kept) does with a lingering `needs_build` row: the sentinel-empty payload parses (`fromMap`'s `as String` succeeds on `''`); the unfiltered exactRetry probe may replay the empty payload → the store fails → the row degrades to `failed` — non-crashing, and the NEW build's rebuild predicate (status OR empty payload) rescues it on return. TC-319-14 exercises the REAL old probe path (unfiltered latest-for-target + `as String` map), not a simulated status-filtered query.
- NOT recoverable once landed: nothing — no data destroyed in either direction; the migration copies rows (rowid included) verbatim.
- Staging: none needed beyond the one-way-floor note; the migration ships with the ordinary client rollout.

## Execution Interpretation And Done Criteria
- Expected RED: TC-02 (empty outbox on HEAD), TC-01 (missing migration), TC-03/04/05/06/07/08/09/11-causal/14 per their documented mechanisms.
- GREEN sentinel: TC-11/12 existing rows; 315's contract untouched.
- Environment blocker: lane's Go legs host-only (expected).
- Scope drift (BLOCKING): any go-relay-server diff; receiver dedupe/upsert changes; retrier ordering changes.

- [ ] All 14 rows closed; both lanes symmetric; three shapes covered.
- [ ] Causal REDs + revert-mutation recorded; migration run-twice + legacy-query legs green.
- [ ] Sentinels + `groups` lane green; completeness PASS; analyzer/diff clean.
- [ ] Zero relay diffs.

## Handoff
- First causal RED command: the TC-319-02 `--plain-name` gate (test written alone first).
- Preservation command: the three-file focused GREEN + the lane.
- Manual registration: none (migration test AUTO-globbed; completeness covers).
- Migration: **DB v105** with test.
- Boundary closure: host; no deploy.
- Unresolved evidence: none.

## Reviewer Findings (2026-08-01, `/tdd-review`, 3-worker audit `wf_fc5b2655-1c3`)

Verdict on v1: **plan-fixes-required** × apply-plan-fixes, **2 blockers** — both on the migration/rollback story, both lead-verified in source: (B1) v1's rollback claim was false in BOTH directions (a full `git revert` reverts the version constant and `onDowngrade: onDatabaseVersionChangeError` at encrypted_db_opener.dart:268 fail-closes every migrated device; and a NULL payload crashes old builds' UNFILTERED latest-for-target probe via `fromMap`'s `as String`, entry:42) → sentinel-empty representation + one-way-floor rollback semantics (v96 precedent); (B2) TC-14's "legacy query" leg was vacuous (simulated status-filtered shapes; the real old path is unfiltered). Confirmed by the factual worker: all three abandonment shapes, both remove-lane gaps, custody keying (inbox.go:1164-1174), the conflict literal in both backends with verbatim propagation to `BridgeCommandException`, rebuild-dependency reachability (stop-if does NOT fire — every builder argument reachable from the retriever's existing params), census (2 saveEntry sites; 2 STAGE_FAILED emitters per lane). REFUTED from v1: "exactRetry probes untouched / needs_build doesn't satisfy the probe" — the probe has no status filter and WOULD replay the empty payload; the fall-through must REUSE the row's PK or a re-tap orphans it. Plan-fixes folded: registry/version-constant ripple + seven pinned chain tests (was entirely unplanned); rowid+index preservation (tiebreak readers at helpers:105/probe:314); four cleanup IN-lists + Move manifest builder + E2E probe hard-cast (needs_build lifecycle across ALL consumers); insert-before-FIRST-throwing-step ordering leg (getMembers throw); conflict-matcher const shape + negative leg; rebuilt plaintext eventId=row PK + timestamp=row.created_at (tombstone stale-guard) + rebuild-time roster by-design with fixture; `attachBuiltPayload` named promotion surface; private-symbol exports; migration test pinned into GROUP_TESTS (102 precedent); result-enum semantics note.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-01 ~15:58Z | RED | send reaction test | TC-319-02 both legs FAIL (build-throw AND roster-throw leave the outbox empty) | causal RED, documented mechanism, ordering leg included | none | migration |
| 2026-08-01 16:00Z | E1 (DB v105) | migration 105 + registry (both lists) + version 104→105 + status const | `flutter test test/core/database/migrations/` → **256 green**: rowid + both indexes preserved, sentinel CHECK enforced in BOTH directions, old-unfiltered-probe parse leg, run-twice; the seven pinned chain-test assertions updated (incl. index arithmetic: 104 is no longer last) | TC-319-01/14 green | none | E2/E3 |
| 2026-08-01 16:02Z | E2/E3 (both lanes) | send/remove use cases, outbox repo+impl+helpers+fake, bootstrap + multi-device harness wiring | needs_build-first staging in BOTH lanes; `saveEntry` returns the write-guard boolean (shape 3) + `STAGE_SKIPPED_PARENT_GONE`; `attachBuiltPayload` promotion; remove-lane unroutable pre-check ported to its choke point | TC-02/08 GREEN; TC-04/09 mechanisms in place | **2 remove tests renegotiated** (EK004 + store-failure): their fixtures had a SOLO roster, so the new pre-check correctly marks them unroutable — gave them a keyed second member (keyless members yield no transports) | E4 |
| 2026-08-01 16:05Z | E4 (retrier + consumers) | retry use case (+3 exports from the two lanes), 4 cleanup IN-lists, retryable query, Move manifest predicate, E2E probe filter | rebuild leg: ORIGINAL transitionId + deterministic id, extension attached, plaintext timestamp anchored to `row.created_at`, rebuild-time roster, fail-soft to `needs_build` with `last_error` | TC-05 GREEN (extension transitionId == row PK on the captured payload) | fake's retryable filter also needed `needs_build` (mirrors the real query) | gates |
| 2026-08-01 16:08Z | mutation | send use case | revert needs_build staging → **both TC-02 legs red**; restored → 31 green | mutation re-red recorded | none | gates |
| 2026-08-01 17:20-18:4xZ | lane triage (self-inflicted, no product defect) | docker-ws/launch_groups_lane_318.sh | Three lane runs read as failures before the cause was found: (1) 8 phantom failures — I ran a **mutation-revert proof and a `git stash` round-trip while the lane was reading the live tree**; (2) one assertion-free timeout failure in a `runAsync`/10s-timeout wired test — **host load**; (3) `LANE_EXIT=0` but unattributable — the root cause of all three: **the launcher had no reap**, so each "restart" left the prior lane alive and up to THREE lanes ran concurrently, appending to one log (a `70:18 +3159 -9` line beside a `01:30 +3342 All tests passed!`) and starving each other of CPU | the suspect tests pass 5/5 isolated and 231/231 in-file on the settled tree | launcher fixed: `pkill` + `pgrep` verification + REFUSE-if-alive; memory entry written | single clean lane |
| 2026-08-01 ~18:5xZ | LANE GREEN | — | single reaped lane on a quiescent host: **`LANE_EXIT=0`, zero `[E]` markers, one sentinel**, Dart array `+3342 All tests passed`, go-mknoon node leg `ok`, relay toolchain contract PASS, relay suite `ok` | attributable green | none | commit |
| 2026-08-01 16:10Z | gates | — | 638 tests across the three reaction suites + migrations + account_migration (one importer version pin bumped); graph-affected dependents 184 green; completeness PASS (migration test registered in GROUP_TESTS); analyzer 0; `git diff --check` clean; **zero go-relay-server diffs**; groups lane running | full host ladder green | none | lane + commit |
