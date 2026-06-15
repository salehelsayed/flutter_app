# 123 — Group-Dissolve Rejoin/Recovery Reconciliation (Defense-in-Depth) (TDD Plan)

Status: Phase 0 + Phase 1 IMPLEMENTED (2026-06-14, Dart-only, uncommitted) — Phase 2 (relay tombstone) deferred per OQ-1; device verification pending. See "Phase 1 closure" at the end.
Date: 2026-06-14
Branch: 121-improvements (the 121 + 122 fixes are IMPLEMENTED but **uncommitted** in the working tree; HEAD = `c79a0fa7` predates them)
Predecessor: this is the **122 OQ-B4 follow-up** — the "defense-in-depth" reconciliation deliberately deferred in `Test-Flight-Improv/122-group-lifecycle-rejoin-dissolve-selection-tdd-plan.md` (B4 section, "Reconciliation / defense-in-depth"). Do NOT re-litigate the 122 terminal-dissolve relaxation — it is **landed and locked** and this plan builds on it.
Source: a 5-thread graph-first recon + adversarial-verify workflow (every load-bearing claim below is graph-confirmed-in-source at file:line on the working tree). The decisive ordering/cost findings were hand-verified in source.

---

## Headline — the convergence machinery already exists; the gap is *reachability*, and it splits into a cheap slice and an expensive slice

When an admin dissolves a group, `dissolveGroup` does **two** things: it publishes the live `group_dissolved` over GossipSub **and** stores a durable, signed offline-replay envelope to the relay group inbox for the frozen recipient set (`dissolve_group_use_case.dart:83-151`, via `publishGroupSystemMessage` → `storeGroupOfflineReplayFromRetryPayload`, `group_system_publish_use_case.dart:110`). A member who misses the live publish *should* re-derive the dissolve from that durable copy on next connect.

**The machinery to do exactly that already exists and works:** `drainGroupOfflineInbox` iterates **all** groups unfiltered by `isDissolved` (`drain_group_offline_inbox_use_case.dart:94`), routes drained `{"__sys":"group_dissolved"}` payloads through the public `groupMessageListener.handleReplayEnvelope` (`drain_..._use_case.dart:586-608` → `group_message_listener.dart:205`) → `_handleGroupDissolved` (`:2061-2078` → `:3993`), and the **122 terminal-dissolve pre-hash relaxation** (`group_message_listener.dart:1804-1810`) lets it converge despite local transition-state drift. So the durable convergence is *built*.

**So why does the field bug ("member stays live") happen?** Two distinct reasons, with very different fix costs:

| Slice | Who | Why the durable dissolve doesn't converge today | Fix cost |
|---|---|---|---|
| **S1 — keyed-offline-missed** | Member had the epoch key, was offline during the live publish, returns within 7d | `rejoinGroupTopics` reads **stale local `isDissolved`** and re-subscribes the topic **before** the drain converges it (`rejoin` runs before `drain` at every recovery site). Plus the incremental drain **cursor** (`drain:292`), the **pre-join-replay skip** (`drain:444-496`), and the **stale-event watermark** (`group_message_listener.dart:2063-2069`) can each silently drop the terminal dissolve. | **Dart-only**, no Go, no gomobile |
| **S2 — keyless / re-added-after-dissolve / >7d / >500-cap** | Re-added member with no epoch key (`SKIP_NO_KEY`); or a member re-added *after* the dissolve (not in the frozen `recipientPeerIds`); or offline >7d; or a chatty group | The relayed dissolve is **AES-encrypted under the group key** → `decryptGroupOfflineReplayEnvelope` **throws** "Missing group replay key" (`group_offline_replay_envelope.dart:289-293`) before any verify; **and** the relay's recipient-authorization filter (`inbox.go:1239-1243`) excludes non-recipients; **and** the relay TTL is 7d / cap 500 (`inbox.go:30-31`). | **Go relay + go-mknoon bridge + native MethodChannel + gomobile rebuild + relay redeploy** |

**Interplay with 122-B3 (important for scoping):** a *successfully* re-added member re-materializes the epoch key during accept (122-B3 `materializeAcceptedGroupInvitePayload`), so they become **keyed** → covered by S1. The keyless slice (S2) is a **compound failure** — the re-add invite was lost **and** the member needs to learn of the dissolve. S1 + 122-B3 cover the realistic field cases; **S2 is tail-risk defense-in-depth.**

**Recommendation:** ship **Phase 1 (S1, Dart-only)** now — it closes the realistic offline window cheaply with no rebuild. Treat **Phase 2 (S2, relay tombstone)** as a separately-scheduled larger effort, gated on whether the re-add-after-dissolve / long-offline tail is in scope (OQ-1).

---

## Methodology — RED-first, prove-the-leak-before-coding, masking-aware

1. **Prove the leak first (Phase 0).** Before writing any production code, author tests that reproduce each slice on the current working tree. The recon strongly suggests S1 *may already partially self-heal via the incidental drain* — so the first move is a failing (or surprisingly-passing) test that establishes whether S1 actually leaks and through which gate (cursor / pre-join-skip / watermark / ordering). **Do not build dead defense-in-depth.**
2. Behavioral fixes get a genuine RED: fails on the current working tree for the documented reason, passes after the GREEN edit. Each RED names the exact current failure and the production edit.
3. **Masking discipline (critical):** the dissolve apply is **idempotent at three layers** (membership watermark `group_message_listener.dart:4027` + `:4335/:4352-4356`; signed-audit-hash dedup `:1722-1754`; deterministic timeline id `group_membership_timeline_message.dart:240-262`). A test that drives convergence using the **same `eventAt`** as an already-applied dissolve will be **no-op'd by the watermark gate** and can falsely pass/fail. **Every RED must drive from a CLEAN non-dissolved local state** (watermark unset or older than the dissolve `eventAt`).
4. **Reuse the public entrypoint, never expose internals.** `_handleGroupDissolved` is a **private** instance method (`group_message_listener.dart:3993`). The only correct route in is the existing public `handleReplayEnvelope({"__sys":"group_dissolved"...})` (`:205`) — which is what the drain already uses. Do **not** widen `_handleGroupDissolved`'s visibility or duplicate dissolve logic (that would bypass the watermark/audit/timeline idempotency).
5. **Minimize blast radius.** Do reconciliation **in / alongside `drainGroupOfflineInbox`** (already wired with `msgRepo` + `GroupMessageListener` + `selfPeerId` at every recovery site) or a small new `reconcileMissedGroupDissolves` use case called next to it — **not** by widening `rejoinGroupTopics({bridge, groupRepo})`, which has 3 production call sites plus device harnesses and a large test-fake surface.
6. Reuse existing harnesses: `rejoin_group_topics_use_case_test.dart` (FakeBridge + InMemoryGroupRepository + `seedGroup` + `captureFlowEvents`), `drain_group_offline_inbox_use_case_test.dart`, `GroupTestUser` + `FakeGroupPubSubNetwork` (the GM-032 offline-converges test already drives `handleReplayEnvelope` + `decodeReplayPayload`), `FakeBridge` group-inbox stubs, and for Phase 2 the Go relay `*_test.go` + `protocol_contract_test.go`.

---

## Field/architecture map (anchors — working tree)

| Concern | Location | Fact |
|---|---|---|
| Rejoin use case | `rejoin_group_topics_use_case.dart:55-59` | `rejoinGroupTopics({required Bridge bridge, required GroupRepository groupRepo, RejoinReason reason})`; `:75` skips `isDissolved`; `:102-127` `SKIP_NO_KEY`; `:131-139` `callGroupJoinWithConfig` re-subscribes. Reads only local state — no durable re-derive. |
| Rejoin→drain ordering | startup_router.dart:654→`:660`; handle_app_resumed.dart:207/282→`:224`; pending_message_retrier.dart `:267` sweep → `:292` rejoin → `:304` drain (main.dart:2178 rejoin closure / `:2202` drain closure) | **rejoin runs BEFORE drain at every recovery site** — the root cause of S1 (re-subscribe a still-"live" group before the durable dissolve converges). |
| Durable dissolve store | `dissolve_group_use_case.dart:83-151`, `group_system_publish_use_case.dart:59-113` | Dissolve stores the **full signed audit container** as the replay plaintext to the relay group inbox, but **only when `recipientPeerIds` is non-empty** (else `inboxStored:true` with no store; `hadBridgeRecoveryGap` only flags the non-empty-store-failed case). |
| Drain path | `drain_..._use_case.dart:62`, `:94` getAllGroups, `:270/:301` retrieve-with-cursor, `:586-608` → `handleReplayEnvelope` | Already routes `{"__sys":"group_dissolved"}` to the listener. |
| Drain suppression gates | cursor `drain:292`; pre-join skip `drain:444-496`; key-missing `group_offline_replay_envelope.dart:289-293` → `drain:388-422` key-repair placeholder | Each can drop a terminal dissolve (cursor advanced past it; relayTimestamp < re-add `joinedAt`; or undecryptable when keyless). |
| Listener convergence + gates | `handleReplayEnvelope:205`; dispatch `:2061-2078`; stale-event gate `:2063-2069`/`:4322-4369`; auth `:2581-2588`+`:2608-2610` (**admin must be currently stored**); audit `signed_group_transition_audit.dart:55-66`; **122 relaxation `:1804-1810`**; apply `_handleGroupDissolved:3993-4043` | A durable admin-signed dissolve converges **iff** the dissolving admin is still a stored `MemberRole.admin` on the rejoining device and the signature/binding verify. |
| Idempotency | watermark `:4027`/`:4335`; audit-hash dedup `:1722-1754`; deterministic timeline id `group_membership_timeline_message.dart:240-262` | Re-apply / live-race is safe (first-writer-wins on watermark). |
| Relay group inbox | `go-relay-server/inbox.go:30` (cap 500, oldest-evict), `:31` (TTL 7d), `:1239-1243` (recipient-auth filter), `:1001-1077` (retrieve, non-destructive), `:1259` Prune, `:1410-1593` action dispatch, `:1517-1518` `from==remotePeer` auth; backends `backend_memory.go:319-414`, `backend_redis.go:576-772` | Per-group append-list, recipient-**authorized** (not per-recipient queue), **no group ack/delete**, TTL+cap eviction only. **No tombstone concept exists.** |
| go-mknoon bridge surface | `bridge.go:2533/2583/2634` (`GroupInboxStore/Retrieve/RetrieveCursor`), `node/group_inbox.go:145-468` | A new dissolve-status command is a **new exported gomobile symbol** → forces `make all` + `pod install`. |
| Frozen wire contract | `protocol_contract_test.go:67-71`, `:116-142` (NET-REL-07) | **Additive** actions/keys allowed if the frozen set is updated. |

---

## Phase 0 — Prove the leak (RED diagnostics; no production code)

Goal: establish exactly which slices leak on the current tree and through which gate, so Phase 1/2 close *real* holes.

**P0-T1 — S1 ordering leak (unit, `rejoin_group_topics_use_case_test.dart` style + drain):** seed a **keyed** group with local `isDissolved == false`, a durable `group_dissolved` available from a `FakeBridge` group-inbox retrieve stub (carrying the signed audit; admin stored as `MemberRole.admin`), and a fresh watermark. Run the **production recovery order** (rejoin then drain) and assert the end state. Expected on current tree: either (a) `group:join` is emitted and `isDissolved` flips only *after* the drain (proving a live-subscription window), or (b) a gate (cursor/pre-join/watermark) drops it and `isDissolved` stays false. **Record which.** This test becomes the Phase 1 regression lock.

**P0-T2 — cursor-skip leak:** pre-advance the persisted inbox cursor (`getInboxCursor`) past the dissolve's position, then run the drain; assert `isDissolved` stays false (dissolve never re-fetched).

**P0-T3 — pre-join-skip leak (re-add):** set the member's `joinedAt` *after* the dissolve's relay timestamp (the re-add resets `joinedAt`); assert `shouldSkipPreJoinReplay` drops the dissolve.

**P0-T4 — stale-watermark leak:** set local `lastMembershipEventAt` watermark *after* the dissolve `eventAt`; assert `_shouldIgnoreStaleMembershipEvent` drops the replayed dissolve.

**P0-T5 — keyless leak (S2):** seed a group with **no** epoch key (`SKIP_NO_KEY`) + a durable encrypted dissolve; run drain; assert it hits the key-repair/undecryptable path (`drain:388-422`) and **never** converges (`isDissolved` stays false). Documents that S2 is unreachable via reuse-drain.

**P0-T6 — recipient-exclusion leak (S2, Go-layer):** in `go-relay-server` test, store a dissolve for `recipientPeerIds=[A,B]`, then retrieve as peer `C` (re-added after dissolve); assert the dissolve is filtered out (`inbox.go:1239-1243`).

Deliverable of Phase 0: a short findings note appended here (which slices leak, which already self-heal) that scopes Phase 1's GREEN edits precisely.

### Phase 0 findings (2026-06-14) — EXECUTED

Diagnostics live in `test/features/groups/application/reconcile_missed_group_dissolves_use_case_test.dart` (PGC-001-style harness: admin-signed `group_dissolved` replay seeded into the relay inbox, local device is a keyed member with `isDissolved == false`). Driving the **real** production recovery path (`rejoinGroupTopics` + `drainGroupOfflineInbox`):

| Slice | Result | Evidence |
|---|---|---|
| **P0-T1 ordering** | **LEAK (transient window)** | rejoin emits a live `group:join` for the still-live group; the *incidental drain that follows* converges it (end-state self-heals **only** because no other gate fires). Confirms the live re-subscribe window is real. |
| **P0-T2 cursor-skip** | **HARD LEAK** | persisted inbox cursor advanced past the dissolve → incremental drain never re-fetches it → `isDissolved` stays false permanently. |
| **P0-T3 pre-join** | **HARD LEAK** | `GROUP_DRAIN_OFFLINE_INBOX_PRE_JOIN_REPLAY_SKIPPED` logged; `shouldSkipPreJoinReplay` drops the terminal dissolve (self `joinedAt` > dissolve relay ts). |
| **P0-T4 watermark** | **HARD LEAK** | `GROUP_MESSAGE_LISTENER_STALE_MEMBERSHIP_EVENT_IGNORED` logged; `_shouldIgnoreStaleMembershipEvent` drops the dissolve (`eventAt <= lastMembershipEventAt`). |
| **P0-T5 keyless (S2)** | out of reach | undecryptable (`Missing group replay key`) → never converges; documents S2 / Phase 2 territory (not built — OQ-1 = Phase 1 only). |

**Conclusion:** the realistic *clean* case self-heals via the incidental drain (PGC-001 passes), but **T2/T3/T4 are real permanent leaks** where the durable dissolve never converges, and **T1 is a real transient live-subscription window**. Phase 1 is therefore NOT dead defense-in-depth. Scoped GREEN edits:
- **reconcile use case (cursor-independent probe, before rejoin)** → closes T1 (converge before re-subscribe), T2 (cursor-independent re-fetch), and routes T3 around the drain-local pre-join gate.
- **listener stale-watermark exemption for terminal dissolve when `isDissolved == false`** → REQUIRED for T4 (the reconcile probe also routes through `handleReplayEnvelope`, so it hits this gate too); benefits both reconcile and the incidental drain.
- **drain `shouldSkipPreJoinReplay` carve-out for `group_dissolved`** → hardens the incidental drain for T3 (defense-in-depth; reconcile already covers it). Also recovers a dissolve a *prior* drain already dropped-and-cursor-advanced.

---

## Phase 1 — Dart-only reconciliation for S1 (keyed-offline, within the 7d window)

Design: a small **`reconcileMissedGroupDissolves`** use case (new file `lib/features/groups/application/reconcile_missed_group_dissolves_use_case.dart`) invoked **before** `rejoinGroupTopics` re-subscribes (or as the first step of the existing drain), with the deps already in scope at every recovery site (`bridge`, `groupRepo`, `msgRepo`, `groupMessageListener`, `selfPeerId`).

**Behavior:** for each group where local `isDissolved == false`, perform a **cursor-independent dissolve probe**: retrieve the group inbox from cursor 0 / `since: group.createdAt` (capped, read-only — reuses `callGroupInboxRetrieveWithCursor`, **no Go change**), scan for a `{"__sys":"group_dissolved"}` envelope authorized for self, and if found route it through `groupMessageListener.handleReplayEnvelope` (which applies the 122 relaxation + idempotency). This is **distinct from the incremental drain** precisely so the advancing drain cursor cannot hide the terminal dissolve.

**GREEN edits (gate exemptions for the terminal event — each paired with its P0 RED):**
- **Ordering:** call `reconcileMissedGroupDissolves` **before** `rejoinGroupTopics` (or make `rejoinGroupTopics` skip re-subscribe for a group the probe just dissolved). Closes P0-T1's live-subscription window. Sites: `startup_router.dart:654`, `handle_app_resumed.dart:207/282`, `pending_message_retrier.dart:292`.
- **Cursor independence:** the probe ignores the incremental drain cursor (P0-T2).
- **Pre-join exemption:** `shouldSkipPreJoinReplay` (`drain:444-496`) must **never** skip a `group_dissolved` system payload — a dissolve is global/terminal, not scoped to the member's join window (P0-T3).
- **Stale-watermark exemption:** `_shouldIgnoreStaleMembershipEvent` (`:4322-4369`) must let a `group_dissolved` apply regardless of the `lastMembershipEventAt` watermark when local `isDissolved == false` (P0-T4). (Keep idempotency for the *already-dissolved* case.)

**Authorization guard (mandatory):** confirm the rejoining device still stores the dissolving admin as `MemberRole.admin`; if a partial roster (post-122-B3) drops the admin, the durable dissolve is rejected (`:2609`). Add a test that seeds the admin correctly and a negative that a non-admin durable dissolve is still rejected.

**RED tests (turn the P0 leaks GREEN):** P0-T1..T4 flip to converged (`isDissolved == true`, `dissolvedBy` set, topic left, no live re-subscribe of the dissolved group). Plus an **idempotency lock** (apply twice / live-race → single timeline row, no duplicate) and a **masking guard** (drive from clean watermark). All in `reconcile_missed_group_dissolves_use_case_test.dart` + an integration variant in `group_membership_smoke_test.dart` (extend the GM-032 pattern: offline member with a stale-but-keyed local state converges via the rejoin probe).

**No-store edge:** add a test for the empty-`recipientPeerIds` dissolve (`group_system_publish_use_case.dart:59-69`) — there is nothing durable to drain; document that S1 cannot help and it is an S2/relay concern.

**Cost:** Dart-only. No `make all`, no `pod install`, no relay redeploy. No gomobile rebuild.

---

## Phase 2 — Relay dissolve tombstone for S2 (keyless / re-add-after-dissolve / >7d) — larger, scheduled

Only undertake if OQ-1 says the S2 tail is in scope. This is a key-independent, recipient-agnostic, cursor-independent, own-TTL **sticky tombstone**.

**P2-1 — Go relay (`go-relay-server`):**
- New backend store separate from the capped per-group queue: `map[groupId]dissolveTombstone` (+ a dedicated Redis key with its **own** longer/own `EXPIRE` — note Redis group inbox has no key-level expire today, `backend_redis.go`). Wired through `GroupInboxBackend` + both backends + `newControlPlaneStores` (`server_bootstrap.go:56-130`).
- Two new actions in the `HandleInboxStream` dispatch (`inbox.go:1410-1593`): `group_dissolve_mark` (store-once at dissolve; authenticate `from==remotePeer`, mirror `:1517-1518`) and `group_dissolve_status` (queryable by **any** member, **no** recipient filter — accept the **signed audit** so the querier can verify admin authenticity without the group key).
- Update the frozen contract NET-REL-07 (`protocol_contract_test.go:67-71`, `:116-142`) — additive keys/actions are allowed but the frozen set MUST be updated. Tests: store/retrieve/auth/TTL on both memory + redis backends.
- **Security:** `group_dissolve_status` with no recipient-auth is a new info-leak surface (probe group existence/dissolve). Mitigate by requiring a valid signed-audit on `mark` and returning only the signed audit (which is already authenticated), and rate/shape the response. Document the privacy trade-off.

**P2-2 — go-mknoon node/bridge:** new exported `Bridge.GroupDissolveStatus(paramsJSON)` (`bridge.go`) + Node method in `node/group_inbox.go` sending `Action:'group_dissolve_status'`; the dissolver also calls `group_dissolve_mark` from `dissolveGroup`. **Forces a gomobile rebuild** (`cd go-mknoon && make all && cd ../ios && pod install`).

**P2-3 — native MethodChannel:** route the new method in `GoBridge.swift` + `GoBridge.kt`.

**P2-4 — Dart:** `callGroupDissolveStatus` helper (`bridge_group_helpers.dart`); `reconcileMissedGroupDissolves` (Phase 1) queries the tombstone **as a fallback** when the inbox probe found nothing (keyless / excluded / >TTL), verifies the returned signed audit **without the group key** (the audit is verifiable from the admin's signing key + stored member binding — confirm this is possible without the AEAD body; if not, the tombstone must carry a key-free verifiable form), and routes it through `handleReplayEnvelope`. `dissolveGroup` emits `group_dissolve_mark` alongside the existing inbox store.

**RED tests:** P0-T5 (keyless) and P0-T6 (recipient-excluded) flip to converged via the tombstone; >7d (inbox pruned, tombstone survives) converges; Go-layer store/query/auth/TTL tests; forgery negative (a tombstone with a bad/non-admin signed audit is rejected on the device).

**Cost:** Go relay change + **relay redeploy to EC2** (`mknoun.xyz`) + go-mknoon + native + **gomobile rebuild**. This is the blast radius that justified deferring it from 122.

---

## Phase 3 — Device verification + residual documentation

- **Pixel↔iPhone, same 3-device dissolve scenario**, capturing fresh `alice/bob/charlie.log`:
  - **S1:** an offline-then-returning **keyed** member logs `GROUP_REJOIN_TOPICS_SKIP_DISSOLVED` (i.e. converged) on the *first* recovery sweep, **not** `GROUP_REJOIN_TOPICS_JOINED` for a dissolved group; no live re-subscription window; the dissolve notice renders and the composer is read-only.
  - **S2 (if built):** a re-added-after-dissolve / long-offline member converges via the tombstone; grep for the new `group_dissolve_status` round-trip.
  - Grep the new logs for `previous_transition_hash_mismatch` (must be **absent** — 122 already fixed it) and confirm `APP_BUILD_INFO` SHA matches the build under test (122-B6).
- Rebuild **both** Flutter and Go from the working tree before any S2 run (`cd go-mknoon && make all && cd ../ios && pod install`).
- **Residual gaps to document (out of scope even with both phases):** offline **> tombstone TTL**; a dissolve that was **never durably stored** (empty-recipients no-store, or actor offline/relay-unreachable at dissolve time — `dissolve_group_use_case.dart:164-165` `hadBridgeRecoveryGap`). These have no recoverable source and should be surfaced as known limitations, not silently "fixed."

---

## Recommended landing order

1. **Phase 0** — prove which slices actually leak (RED diagnostics). Gate the rest on the findings; do not build dead defense-in-depth.
2. **Phase 1 (S1, Dart-only)** — the cursor-independent dissolve probe + ordering + gate exemptions + auth guard. Highest ROI, no rebuild, closes the realistic offline window. Ship first.
3. **Phase 2 (S2, relay tombstone)** — only if OQ-1 puts the keyless/re-add-after-dissolve/long-offline tail in scope. Schedule as its own effort (Go + native + gomobile + relay redeploy).
4. **Phase 3** — device re-verification + residual-limit documentation.

---

## Gate / acceptance per phase

- Per phase: the listed RED tests fail on the current working tree for the documented reason and pass after the GREEN edit; the idempotency lock and the auth negative stay green throughout; masking guards drive from a clean non-dissolved watermark.
- Suite gates (run `-j 1` to avoid the known shared-global-gate parallel flake): `flutter test test/features/groups/`, plus `dart analyze` showing zero new issues. For Phase 2: `cd go-mknoon && go test ./...` and `cd go-relay-server && go test ./...` (incl. the updated `protocol_contract_test.go`).
- Device re-verification as in Phase 3.

---

## Open questions (owner decisions)

- **OQ-1 (primary, scope fork):** Is the **S2 tail** (keyless-after-failed-re-add, member re-added *after* dissolve, offline >7d) in scope now, given (a) its cost is Go relay + native + gomobile + relay redeploy, and (b) 122-B3 already makes a *successfully* re-added member keyed (→ covered by the cheap S1 Phase 1)? Recommend: **ship Phase 1 now; schedule Phase 2** only if field evidence shows the compound-failure tail actually bites.
- **OQ-2:** Phase 1 placement — a **new `reconcileMissedGroupDissolves` use case** called before rejoin (clean separation, recommended) vs. **folding the dissolve probe into `drainGroupOfflineInbox`** (fewer call-site edits, but mixes concerns). Recommend the new use case.
- **OQ-3 (Phase 2 privacy):** is an any-member-queryable `group_dissolve_status` (a new group-existence/dissolve probe surface) acceptable, mitigated by requiring/returning a signed admin audit? Or should the tombstone remain recipient-scoped (which fails to cover the re-add-after-dissolve case — the main reason S2 exists)?
- **OQ-4:** the empty-`recipientPeerIds` no-store dissolve and the actor-offline-at-dissolve `hadBridgeRecoveryGap` case have **no durable source** — accept as documented residual, or have the dissolver retry the durable store on its own next recovery sweep?

---

## Evidence appendix (recon anchors — working tree, graph-confirmed)

- **Root-cause ordering:** `rejoinGroupTopics` (`rejoin_group_topics_use_case.dart:55`, skip-dissolved `:75`) runs **before** `drainGroupOfflineInbox` at startup (`startup_router.dart:654`→`:660`), resume (`handle_app_resumed.dart:207/282`→`:224`), and the retrier sweep (`pending_message_retrier.dart:292`→`:304`).
- **Durable store:** `dissolve_group_use_case.dart:83-151` (recipientPeerIds `:83-87`, sign `:90-110`, inboxPayload `:119-130`, publish `:134`), `group_system_publish_use_case.dart:59-113` (conditional store `:59-69`, store path `:110`).
- **Convergence machinery (already built):** `drain_..._use_case.dart:94` (all groups), `:586-608` (→ `handleReplayEnvelope`), `group_message_listener.dart:205` (public entry), `:2061-2078` (dispatch), `:3993-4043` (`_handleGroupDissolved`), **122 relaxation `:1804-1810`**.
- **S1 suppression gates:** cursor `drain:292`; pre-join skip `drain:444-496`; stale-watermark `group_message_listener.dart:2063-2069` / `:4322-4369`.
- **S2 blockers:** keyless decrypt throw `group_offline_replay_envelope.dart:289-293`; relay recipient-auth filter `go-relay-server/inbox.go:1239-1243`; TTL 7d `:31`; cap 500 oldest-evict `:30`.
- **Auth/idempotency:** admin-auth `group_message_listener.dart:2608-2610`; requiresSignedAudit `signed_group_transition_audit.dart:55-66`; watermark dedup `:4027`/`:4335`; audit-hash dedup `:1722-1754`; deterministic timeline id `group_membership_timeline_message.dart:240-262`.
- **Go tombstone surface:** action dispatch `inbox.go:1410-1593`, store auth `:1517-1518`, bootstrap `server_bootstrap.go:56-130`, contract NET-REL-07 `protocol_contract_test.go:67-71`/`:116-142`; bridge `go-mknoon/bridge/bridge.go:2533/2583/2634`, node `node/group_inbox.go:145-468`.
- **Test harnesses:** `rejoin_group_topics_use_case_test.dart` (setup `:67-73`, `seedGroup` `:76-103`, `captureFlowEvents` `:16-43`, skips-dissolved `:1678-1750`); `GroupTestUser` GM-032 offline-converges (`handleReplayEnvelope` + `decodeReplayPayload`); `FakeBridge` group-inbox stubs; Go `protocol_contract_test.go`.

---

## Phase 1 closure (2026-06-14) — IMPLEMENTED (Dart-only, OQ-1 = Phase 1 only)

**Scope shipped:** Phase 0 (diagnostics) + Phase 1 (S1, Dart-only). Phase 2 (relay tombstone, S2) **not built** (OQ-1 owner decision = Phase 1 only). All changes uncommitted on `121-improvements`.

**Production changes**
- **NEW** `lib/features/groups/application/reconcile_missed_group_dissolves_use_case.dart` — `reconcileMissedGroupDissolves({bridge, groupRepo, groupMessageListener, selfPeerId, pageSize=50, maxPages=12})`. For each locally-live group it does a **cursor-independent, read-only** inbox scan from cursor 0 (it never advances the drain cursor), reuses the shared `decodeInboxMessage` to decrypt each message, and routes the first `{"__sys":"group_dissolved"}` it finds through the public `GroupMessageListener.handleReplayEnvelope` (which owns auth + signed-audit verify + the 122 relaxation + all idempotency). Keyless/undecryptable messages throw inside decode and are skipped (S2). `maxPages=12 × 50 = 600` covers the relay's 500-cap; a truncated scan emits `GROUP_RECONCILE_DISSOLVES_TRUNCATED` (no silent cap).
- **Listener watermark exemption** `group_message_listener.dart` `group_dissolved` dispatch (~:2061): a terminal dissolve now applies even when the local membership watermark is *ahead* of the dissolve `eventAt`; the stale-event gate is consulted **only when the group is already dissolved** (idempotency preserved → single timeline row). Fixes **T4** for both reconcile and the incidental drain.
- **Wiring** `reconcileMissedGroupDissolves` runs at every recovery site: `startup_router.dart` (`_doStartP2P`), `handle_app_resumed.dart` (both Branch A full + Branch B rejoin-only), and the `main.dart` retrier rejoin closure (`rejoinGroupTopicsWithRecoveryAckEligibilityFn`).

**ORDERING DECISION (deviation from the plan, deliberate): `rejoin → reconcile → drain`, NOT reconcile-before-rejoin.**
The plan proposed reconcile *before* rejoin to close the T1 window. Implementing that **regressed IR-018** (`group_startup_rejoin_smoke_test.dart`): the cursor-independent inbox scan, when run before rejoin, delays topic re-subscription, so live messages arriving during the scan window are missed for *active* groups (the common case). Re-analysis: the actual "member stays live" field bug is the **permanent non-convergence (T2/T3/T4)**, which reconcile fixes **regardless of order**; **T1 is a harmless transient** (re-subscribe a dissolved group, then reconcile converges + `callGroupLeave` it immediately). So rejoin runs first (active groups re-subscribe instantly), then reconcile converges any missed dissolve (and leaves it), then drain. The T1 regression lock now asserts the group **does not stay live** (converges + a `group:leave` is issued) rather than "0 joins". IR-018 passes with this order.

**Why no in-drain pre-join carve-out (T3):** the inner `__sys` type lives inside the AES-GCM plaintext, invisible to `shouldSkipPreJoinReplay` (which runs *before* decode). Rather than restructure drain to decode-before-skip, the cursor-independent reconcile probe covers T3 (it decodes everything and bypasses the drain-local pre-join gate) **and** recovers a dissolve a prior drain already dropped-and-cursor-advanced. Drain is left untouched (minimal blast radius).

**Tests** `test/features/groups/application/reconcile_missed_group_dissolves_use_case_test.dart` (11 tests): baseline converge; T1 (rejoin→reconcile converges + leaves, not stays-live); T2 (drain can't / reconcile re-fetches past the cursor); T3 (drain pre-join-skips / reconcile converges); T4 (drain + reconcile both converge via the watermark exemption); reconcile no-op when no dissolve; idempotency lock (replay twice → single timeline row); masking guard (already-dissolved → second reconcile no-op); auth negative (non-admin not converged + `UNAUTHORIZED_MEMBERSHIP_EVENT`); S2 keyless not converged. Each P0 RED was proven on the raw path first (T2/T3/T4 keep an explicit `drain → still false` assertion).

**Gates (all -j 1):** `flutter test test/features/groups/` = **2055/2055** (IR-018 green via the reorder). `flutter test test/core/lifecycle/ test/core/services/pending_message_retrier_test.dart test/features/identity/.../startup_router*` = **183/1 failed**, the single failure being **pre-existing & independent of this work** (`handle_app_resumed_group_recovery_test.dart` "blocks admin-only group actions … removal settles" expects a hard-delete `null`, but 122-B3 retains self-removed groups read-only; confirmed failing with reconcile no-op'd — a 122-B3 reconciliation miss, NOT a 123 regression). `dart analyze` = zero new issues in touched files.

**Residual / out of scope (documented limits):** S2 tail (keyless / re-added-after-dissolve / >7d / >500-cap) — needs the Phase 2 relay tombstone (deferred). Empty-`recipientPeerIds` no-store dissolve and actor-offline-at-dissolve `hadBridgeRecoveryGap` — no durable source (OQ-4). Reconcile re-scans each live group's inbox (≤relay cap) on every recovery sweep — accepted read-only cost, logged-on-truncate.

**Pending:** device verification (Phase 3 — Pixel↔iPhone 3-device dissolve repro, grep `GROUP_RECONCILE_DISSOLVES_*`); no rebuild/redeploy required (Dart-only).
