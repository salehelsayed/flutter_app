# 173 - NET-REL-07 relay regressions: restore 1:1 inbox evict-oldest (oversized-push = no-op)  (Bug)

Status: implemented (host-green 2026-07-02) — relay redeploy (step 10) + TC-07 sim leg still owed
Spec: free-text intent (no formal spec) — from the 2026-06-28 relay-redeploy audit. Binding rail: `Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md` (NET-REL-07).

> **READ FIRST — recommendation vs the requested approach.** This plan was requested as a *parallel-relay migration* for two NET-REL-07 regressions. A 6-agent verify→refute grounding at HEAD (`5d54c028`) concluded **neither regression warrants a parallel relay**: Regression 1 is a backward-compatible *improvement* (no relay change), and Regression 2's safe fix is an **in-place revert to evict-oldest**, which is backward-compatible *by construction* — the opposite of NET-REL-07 rule 3's trigger (rule 3 governs *adding/keeping a new breaking behavior* on the shared relay, not *reverting* one). The parallel-relay path is therefore **REFUTED** for this work and documented below only as the contingency for a future genuinely-breaking change (the infra already exists and is on by default). The plan implements the in-place fix.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-28 | Evidence Collector | inbox.go, inbox_store.go, backend_memory.go, backend_redis.go, limits.go, protocol_contract_test.go, config.go, relay_selector.go, feature_flags.go, NET-REL-07 | R1 not-breaking; R2 breaking-but-fixable-in-place; multi-relay infra exists+on-by-default | Build matrix |
| 2026-06-28 | Planner | (above + tier-matrix/sufficiency refs) | Restore 1:1 evict-oldest; parallel-relay REFUTED | Emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-02 | contract extraction (git status --short) | — | pre-existing dirty = another session's 188 doc/test edits + graphify artifacts; none overlap this plan | scope confirmed | RED |
| 2026-07-02 | RED tests added | protocol_contract_test.go (TC-01), backend_memory_test.go NEW (TC-02), backend_redis_test.go (TC-03 replaces :448), inbox_test.go (TC-04 replaces :2327), limits_test.go (TC-05 replaces :19 + TC-06 lock), metrics_test.go (rename→TestInboxCappedAndTTLPruneTelemetry, capped+1/rejected_full+0) | `GOTOOLCHAIN=go1.25.0 go test . -run 'FullInboxStoreStaysOK\|StoreAtCapEvicts\|EvictOldestWhenInboxFull\|GroupInboxStillEvicts\|InboxCappedAndTTL'` → 5 FAIL exactly on rejected_full/ERROR-at-cap; TestGroupInboxStillEvicts PASS (lock) | RED for expected reason. **The RED baseline IS the mutation proof** (committed reject-at-cap code == the revert mutation for every TC) | implement |
| 2026-07-02 | implementation | backend_memory.go:130 evict+rebuild+inboxCappedCounter.Add(overflow); backend_redis.go Store evict-in-tx, counter after commit (retry-safe, `pruned` pattern); limits.go:123 evict + inner rebuild + ServerLimits doc fix (:26-27 "rejected"→"evicted") | scoped files only; RejectedFull enum + rejected_full counter + inbox.go dead branch + client INBOX_FULL parser all KEPT (Scope Guard) | none | direct GREEN |
| 2026-07-02 | direct GREEN | + server_bootstrap_test.go:298 flip (configured-limits test, not in plan inventory — same class) | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` ok 12.3s · `-race ./...` ok 14.5s · `-tags integration ./...` ok 12.7s | reds now green | cross-pkg |
| 2026-07-02 | preservation GREEN (cross-pkg TC-08) | go-mknoon/integration/local_relay_harness_test.go (harness storeInbox → evict-oldest, mirrors real relay), relay_test.go (TestInboxStoreFull_TypedRejectionAgainstLocalRelay → TestInboxStoreAtCap_EvictsOldestDeliversNewest). bridge_test.go:845 + commands_test.go:212 + node/inbox_parse_test.go KEPT unchanged (synthetic-injection client-tolerance tests — parser preserved per Scope Guard) | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` ALL ok (node 445s, bridge 197s) · `-tags integration ./integration/...` ok 93s · interop_vectors.json restored | sentinels green | lint |
| 2026-07-02 | named gates | — | `make lint` (go vet + golangci-lint --new-from-rev=HEAD) → 0 issues · `git diff --check` clean | gate green | record |
| 2026-07-02 | TC-11 media audit | — | media.go:185-186: per-peer cap DELETES/evicts (`peer_cap` counters) — no OK→ERROR inversion on media; asymmetry N/A | audit clean, no fix needed | — |

## Source Of Truth
- Spec / intent: this doc + NET-REL-07 (`Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md`)
- Gate definitions: `go-relay-server/Makefile` + `GOTOOLCHAIN=go1.25.0 go test ./...`; `scripts/run_test_gates.sh reliability-sim`
- Frozen contract: `go-relay-server/protocol_contract_test.go`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready (Go relay change; host/Go-test closure + one reliability-sim 1:1 leg). **All Go tests run under `GOTOOLCHAIN=go1.25.0`** (Go 1.26 panics quic-go session-ticket — see memory `feedback_go126_quicgo_session_ticket_panic`).

## Exact Problem Statement
The 2026-06-28 relay redeploy (commit `c0eb29b9`) introduced two client-observable changes vs build 106 (`8ba68cd7`):

- **R1 — oversized push fallback.** `go-relay-server/inbox.go:296-311`: when `pushDataSize(data) > maxPushDataBytes` (const `4000`, `:55`), the 1:1 `new_message` push drops `kem/ciphertext/nonce` and sends a content-free visible alert carrying only `type,sender_id,preview_unavailable=1,[message_id]` (`buildOversizedFallbackPushMessage:478`). Build 106 had no size check.
- **R2 — inbox capacity inverted (OK→ERROR).** `inbox_store.go:8` new `InboxStoreResultRejectedFull`; `backend_memory.go:130-132`, `backend_redis.go:301-308`, `limits.go:123-125` now **reject** a 1:1 store at `maxMessagesPerPeer` (100) instead of **evicting the oldest**; `inbox.go:1613-1620` maps it to `Status:"ERROR", Error:"INBOX_FULL"` and `inbox.go:878-885` fires **no push**. Build 106 always evicted-oldest and returned `Stored` (→ `Status:"OK"`, push fired).

Impact: R2 is genuinely **breaking** for un-updated clients. The build-106 client store path is `if resp.Status != "OK" { return error }` (`git show 8ba68cd7:go-mknoon/node/inbox.go:121-122`) with **no `INBOX_FULL` branch** — so a send to a 100-full recipient that build 106 always saw succeed now hard-fails, the **newest** message is dropped, and no push fires. Frozen-contract CI did not catch it: `protocol_contract_test.go:174` (`TestStatusValueContract_Frozen`) only stores **once** (→ OK) and **never fills the inbox**, so the OK→ERROR inversion is invisible.

What must improve:
1. A 1:1 store to a full inbox must return `Status:"OK"` and deliver the newest message (build-106 contract) — i.e. restore evict-oldest on the 1:1 path.
2. The frozen-contract test must freeze the full-inbox→OK behavior so this cannot silently re-invert.

What must stay unchanged (→ preserved-green sentinels):
- The GROUP inbox path (already evicts oldest — `backend_memory.go:377`, `limits.go:30`); the additive response fields (`storeStatus/occupancy/capacity/expiresAtMs`) old clients ignore; the protocol IDs + frozen response-key set (`protocol_contract_test.go:40,120`).
- The HEAD client's defensive `INBOX_FULL` parser (`go-mknoon/node/inbox.go:97-105`, `lib/core/services/inbox_store_outcome.dart:62/69`) — kept dead-but-tolerant.

## Root Cause (verify → refute confirmed)
- **R2 (the only real bug):** `backend_memory.go:130-132` / `backend_redis.go:301-308` / `limits.go:123-125` return `InboxStoreResultRejectedFull` at cap (HEAD) vs `git show 8ba68cd7:...backend_memory.go` which sliced `messages = messages[len-cap+1:]` + `rebuildMessageIds` then appended → `Stored`. The 1:1 path diverged from the GROUP path (still evicts) and from every shipped binary's expectation. **Verdict: BREAKING_FIXABLE_IN_PLACE (high confidence).**
- **R1:** the message body is **never** in the push — even the happy path is a ciphertext-only silent push (`buildCiphertextOnlyPushMessage:426`); the body arrives via the **inbox drain** on open. Build 106's oversized push was >4096 B → **FCM-rejected → no notification at all**; the new fallback sends a *visible* alert → strictly better. `preview_unavailable` has **zero consumers** in `lib/`/`go-mknoon/` (grep-confirmed). **Verdict: NOT_BREAKING (high confidence) → no relay change.**

**Refuted / do-NOT-build:**
- **Parallel/second-relay migration.** Infra exists and is correct — `DefaultRelayAddresses()` pool (`config.go:181`), `NewRelaySelector`/`buildRelaySelector` (`relay_selector.go:20-56,206-218`), `EnableMultiRelayRouting` default true (`feature_flags.go:78`), Dart `MKNOON_RELAY_ADDRESSES`/`MKNOON_ENABLE_MULTI_RELAY_ROUTING` (`p2p_bridge_client.dart:17-41`), distinct-peerID via `RELAY_PRIVATE_KEY` (`server_config.go:84-93`), shared state via same `REDIS_URL`+`REDIS_PREFIX` (`server_bootstrap.go:55-131`). **But it is the wrong tool:** rule 3 is for keeping a breaking change you *must* ship; here the fix is to *revert* the break, which all shipped binaries already handle. Building relay #2 + drain-telemetry + retirement is unwarranted cost/risk. (Note for any FUTURE genuinely-breaking change: inbox RETRIEVE/ACK use `ForEachWithResult` first-success → a client drains exactly **one** relay; "drain old traffic" therefore relies on the **shared Redis backend**, not cross-relay reads. Token registration fans out (`inbox.go:797`).)
- A relay-side "fix" for R1 (re-adding encrypted keys to the oversized push recreates the >4096 FCM drop).
- Removing the `RejectedFull` enum / `relay_inbox_rejected_full_total`+`relay_inbox_capped_total` counters / the client `INBOX_FULL` parser — keep as dead-but-tolerant (deletion is churn + weakens future robustness).
- Version negotiation — none exists, none needed once the contract is restored.

## Real Scope
In scope (relay Go + test migrations; `GOTOOLCHAIN=go1.25.0`):
- Restore **evict-oldest + `Stored`(→OK)** for the 1:1 inbox store in all three backends: `backend_memory.go:130-132`, `backend_redis.go:301-308`, `limits.go:123-125` (limited/test backend, keep parity). Result: `InboxStore.Store` (`inbox.go:878`) hits success → push fires (`:904-907`) → `Status:"OK"` (`:1622`).
- Keep the `RejectedFull` enum + counters as dead/observability; keep `relay_inbox_capped_total` incrementing per eviction (parity with group's `groupInboxCappedCounter`).
- **Extend the frozen contract:** add a fill-to-cap case to `protocol_contract_test.go::TestStatusValueContract_Frozen` asserting a full-inbox 1:1 store → `Status:"OK"` (negative-control discipline: this is the test whose absence let the regression ship).
- Migrate the existing tests that pin the NEW reject contract to the restored OK contract (see matrix).
- (Optional, low-tier) a relay `pushDataSize` boundary test + a Dart defensive test that drain-on-open ignores `preview_unavailable` — not load-bearing.

Out of scope (owning work named):
- The CLIENT silent-rejected-drop on receive → plan **#172** (different subsystem).
- Any parallel-relay stand-up (refuted).
- The "reject-full so the online sender retries truthfully" *feature* (R2's design rationale): if still wanted, it requires a NEW client that acts on `INBOX_FULL` + a new protocol-ID/relay — **defer to a future client+relay**, do not keep it on the live relay.

## Files To Inspect Next
Production: `go-relay-server/backend_memory.go:130-132`, `backend_redis.go:301-308`, `limits.go:30,123-125`, `inbox.go:55,296-311,426,462,478,878-885,904-907,1613-1630`, `inbox_store.go:6-8`, `metrics.go:109-117`.
Direct tests + integration tests: `protocol_contract_test.go:120-200`, `limits_test.go:19,71,92`, `backend_redis_test.go:448,463`, `inbox_test.go:2327,2368,2393`, `metrics_test.go:89,113,161`; cross-pkg: `go-mknoon/integration/relay_test.go:554-561`, `local_relay_harness_test.go:504-506`, `bridge_test.go:845-851`, `node/inbox_parse_test.go`, `cmd/testpeer/commands_test.go:212`.
Dependency-only context: client tolerance `go-mknoon/node/inbox.go:97-105`, `lib/core/services/inbox_store_outcome.dart:62,69`, `lib/features/conversation/application/send_chat_message_use_case.dart:1151`; group baseline `backend_memory.go:377`, `group_inbox_test.go:808`.

## Existing Tests Covering This Area
- `limits_test.go:19 TestFiniteLimits_RejectNewWhenInboxFull` — pins NEW 1:1 reject (MUST flip to evict+OK).
- `limits_test.go:71/92` — group path EVICTS (stays green; the model to mirror).
- `backend_redis_test.go:448 TestRedisInboxBackend_StoreRejectsNewWhenFull` — NEW redis reject (MUST flip).
- `inbox_test.go:2327 TestHandleInboxStream_StoreRejectsWhenFull` — end-to-end Status=ERROR/INBOX_FULL/no-push (MUST flip to OK + push + oldest evicted).
- `metrics_test.go:89/113/161` — reject-full + capped counters + scrape contract (capped stays; rejected_full becomes dead → adjust expectation, keep the scrape name to avoid Grafana breakage).
- `protocol_contract_test.go:157 TestStatusValueContract_Frozen` — never fills the inbox (**the coverage gap**).
- Cross-pkg INBOX_FULL assertions: `relay_test.go:554-561`, `local_relay_harness_test.go:504-506`, `bridge_test.go:845-851`, `cmd/testpeer/commands_test.go:212` — end-to-end overflow MUST flip to OK; PARSER tests (`node/inbox_parse_test.go`) stay (HEAD client must still tolerate a stray INBOX_FULL).

Missing coverage gaps: (a) no test pins the build-106 evict-oldest/OK-on-full contract; (b) R1 push/FCM path has no contract coverage; (c) no reliability-sim covers "send to a full inbox → delivered, oldest displaced."

Already in curated family arrays?: these are **Go** tests (run via `go test ./...`, not the Flutter `run_test_gates.sh` arrays). The reliability-sim leg (TC-07) registers via `check_reliability_simulation_discovery.sh`.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `go-relay-server/protocol_contract_test.go`::`TestStatusValueContract_FullInboxStoreStaysOK`  (**highest value — the gap that shipped the bug**)
   - Tier: relay end-to-end (real mocknet stream); Shape: over one peer, store `maxMessagesPerPeer`+1 messages, assert the final store → `Status:"OK"` (and oldest evicted, occupancy==cap).
   - RED on HEAD because: final store returns `Status:"ERROR", Error:"INBOX_FULL"` (`inbox.go:1613`).
   - GREEN after fix asserts: `Status:"OK"`, occupancy==cap, oldest id gone, newest present.
   - Mutation that re-reds: re-introduce the `RejectedFull` reject branch in any backend → red.
2. `go-relay-server/backend_memory_test.go`::`TestMemoryInbox_StoreAtCapEvictsOldestReturnsStored`
   - Tier: relay unit; RED: returns `RejectedFull` (`backend_memory.go:130`); GREEN: returns `Stored`, len==cap, oldest evicted (mirror `group_inbox_test.go:808`). Mutation: revert evict→reject → red.
3. `go-relay-server/backend_redis_test.go`::`TestRedisInbox_StoreAtCapEvictsOldestReturnsStored`  (replaces `:448`)
   - Tier: relay integration (miniredis/real); RED: `:448` asserts `RejectedFull`; GREEN: `Stored`, oldest two-of-N evicted. Mutation: revert → red.
4. `go-relay-server/inbox_test.go`::`TestHandleInboxStream_StoreAtCapEvictsAndPushes`  (replaces `:2327`)
   - Tier: relay end-to-end; RED: `:2327` asserts ERROR/INBOX_FULL/no-push; GREEN: `Status:"OK"`, push fired, oldest evicted, occupancy==cap. Mutation: revert → red.
5. `go-relay-server/limits_test.go`::`TestFiniteLimits_EvictOldestWhenInboxFull`  (replaces `:19`)
   - Tier: relay unit; RED: `:19` asserts reject; GREEN: evict+Stored. Mutation: revert → red.
6. `go-relay-server/limits_test.go`::`TestGroupInboxStillEvicts`  (preservation lock — group must NOT change)
   - Tier: relay unit; lock at `:71/92`; reds only if group eviction is accidentally touched. Mutation: change group→reject → red.
7. reliability-sim 1:1 `send to a full relay inbox → delivered, oldest displaced`
   - Tier: simulator E2E (real bridge/relay); RED on HEAD: send to a 100-full peer → store ERROR, message not delivered; GREEN: delivered (oldest displaced), receiver sees it. Mutation: revert evict → sim red. Closure gate. PROD-CRITICAL wire leg.
8. (optional, low) `go-relay-server/inbox_test.go`::`TestPushDataSize_OversizedDropsCiphertextKeepsVisibleAlert` — pins R1 fallback is intentional + bounded (keeps existing `:1220` semantics; documents no-regression). Not load-bearing.
9. (optional, low) `test/core/services/inbox_store_outcome_test.dart`::`full-inbox send now resolves via OK path; INBOX_FULL parser still tolerated` — Dart defensive; asserts the dead-but-tolerant branch survives.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 full-inbox→OK frozen | wire contract (mocknet) | relay e2e | protocol_contract_test.go::TestStatusValueContract_FullInboxStoreStaysOK | final store ERROR/INBOX_FULL (:1613) | re-add reject branch | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test; existing _test.go) |
| TC-02 memory evict | store-when-full semantics | relay unit | backend_memory_test.go::StoreAtCapEvictsOldestReturnsStored | returns RejectedFull (:130) | revert evict→reject | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-03 redis evict | durable store-when-full | relay integration | backend_redis_test.go::StoreAtCapEvictsOldestReturnsStored | :448 asserts RejectedFull | revert→reject | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-04 e2e OK+push+evict | end-to-end store path | relay e2e | inbox_test.go::StoreAtCapEvictsAndPushes | :2327 ERROR/no-push | revert→reject | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-05 limited backend evict | store-when-full | relay unit | limits_test.go::EvictOldestWhenInboxFull | :19 asserts reject | revert→reject | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-06 group unchanged | preservation lock | relay unit | limits_test.go::TestGroupInboxStillEvicts | (lock; reds only if group touched) | change group→reject | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-07 e2e sim closure | real bridge/relay | simulator | reliability-sim `1to1` full-inbox→delivered | send to full inbox not delivered | revert evict | `./scripts/run_test_gates.sh reliability-sim` then `/sims 1to1 --only N` | classify_path() case + `--scenario` |
| TC-08 cross-pkg overflow | client round-trip | Go integration | relay_test.go / local_relay_harness_test.go / bridge_test.go overflow→OK | assert INBOX_FULL (:554/:504/:845) | revert evict | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |
| TC-09 client tolerance | parser preservation | unit | inbox_store_outcome_test.dart::INBOX_FULL still tolerated | (lock) | remove parser | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (glob) |
| TC-10 R1 boundary (opt) | push construction | relay unit | inbox_test.go::OversizedDropsCiphertextKeepsVisibleAlert | (documents intended R1) | n/a (no R1 change) | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO (go test) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-03 — under the **Redis durable** backend, an at-cap inbox evicts oldest and the surviving 100 **persist across a relay restart** (assert via a reopen/new-backend-instance read), proving the evict is durable, not just in-memory.
- **Sibling-surface consistency:** TC-06 locks GROUP still evicts. **Add TC-11 (audit):** the MEDIA inbox store-when-full path (`media.go`, cap relaxed 50→100) — confirm it does NOT have the same OK→ERROR inversion, or fix it for parity. NOT N/A — the redeploy also touched media caps.
- **Destructive-action side-effects:** TC-02/03/04 assert evict removes **the oldest** (by id) and preserves the **newest** + fires the push + dedup-by-id still holds — not merely that the store returns OK.
- **Invariant re-verification under new transitions:** TC-01/04 — the restored evict transition re-verifies INV-A ("1:1 store always returns OK") AND INV-B ("a fresh store always fires exactly one push"), asserting the full post-store response (status, occupancy, capacity, push count).

## Invariants (locked by tests)
- INV-A: a 1:1 store to a full inbox returns `Status:"OK"` (build-106 contract) → TC-01/04/05.
- INV-B: every fresh (non-duplicate) 1:1 store fires exactly one push → TC-04.
- INV-C: GROUP + MEDIA store-when-full semantics are consistent with 1:1 (all evict) or a deliberate asymmetry is test-locked → TC-06/TC-11.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`. Add RED tests TC-01..06,08 (+ optional 09,10); run `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` and confirm they fail for the documented reasons.
2. `backend_memory.go:130-132` → restore evict-oldest (`messages = messages[len-cap+1:]` + `rebuildMessageIds`, append, return `Stored`).
3. `backend_redis.go:301-308` → restore trim-then-append (`values = values[len-cap:]`, return `Stored`).
4. `limits.go:123-125` → evict (limited/test backend parity).
5. Leave `InboxStoreResultRejectedFull` + counters in place (dead/observability); keep `relay_inbox_capped_total` incrementing per eviction.
6. Extend `protocol_contract_test.go::TestStatusValueContract_*` with the fill-to-cap→OK assertion (TC-01).
7. Migrate cross-pkg overflow assertions (TC-08) to OK; keep the parser tests.
8. Audit media store-when-full (TC-11); fix or test-lock asymmetry. Stop-if: media reject-when-full is intentional + a NEW client depends on it → document asymmetry, do not silently change.
9. Rerun relay + go-mknoon Go suites (go1.25.0) → reliability-sim 1:1 (TC-07).
10. Redeploy the relay with the reverted store logic (operator step; no parallel relay, no flag, no live-relay "flip" — restoring the build-106 contract is backward-compatible by construction).

## Risks And Edge Cases
- **Ops visibility:** after the revert `relay_inbox_rejected_full_total` stops incrementing on 1:1 (expected); keep the metric name (TC scrape) so Grafana panels don't error.
- **Group/media drift:** ensure only the 1:1 path changes (TC-06/TC-11).
- **Client double-handling:** HEAD client keeps a dead INBOX_FULL branch — harmless (TC-09).
- **Deploy timing (NET-REL-07):** redeploy in place is safe *only because this reverts to the already-shipped contract*; do NOT pair it with any other breaking relay change in the same deploy.

## Device/Relay Proof Profile
Go-test + host for TC-01..06,08,09; **reliability-sim 1:1 (TC-07) is the end-to-end closure gate** (proves a send to a full inbox is delivered through the real bridge/relay). No device-proof needed (no OS boundary).
Closure scenario: `/sims 1to1 --only N`. Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1…` (see `/sims`). The live relay env (`.env`/`se.pem`) connects to PROD — relay redeploy is an explicit operator action, not part of the test run.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before edits) — must FAIL for the documented reason
cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run 'TestStatusValueContract_FullInboxStoreStaysOK|StoreAtCapEvicts' ; cd ..

# Direct GREEN (after fix) — relay suite + race
cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... && GOTOOLCHAIN=go1.25.0 go test -race ./... ; cd ..
# go-mknoon cross-pkg overflow assertions now expect OK
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... ; cd ..

# Lint
cd go-relay-server && GOTOOLCHAIN=go1.25.0 golangci-lint run ; cd ..

# Dart defensive (TC-09)
./scripts/run_host_test_gates.sh core-host-all

# Simulator discovery + run (TC-07)
./scripts/check_reliability_simulation_discovery.sh   # new full-inbox→delivered 1:1 scenario MUST list
# /sims 1to1 --list → note --only N → /sims 1to1 --only N

# Hygiene
flutter analyze            # 0 new issues (Dart side)
git diff --check
```
(No `DB v##` — the relay has no client DB schema; the inbox is Redis/memory, not SQLCipher.)

## Known-Failure Interpretation
- Expected RED: TC-01..05,08 before the revert.
- Expected FLIP: existing `TestFiniteLimits_RejectNewWhenInboxFull`/`...StoreRejectsWhenFull`/redis reject tests and cross-pkg INBOX_FULL overflow tests are intentionally rewritten — their old form failing post-fix is correct, not a regression.
- Pre-existing dirty: shared tree (`go-mknoon/node/node.go` etc. modified by concurrent work) — snapshot first; do not revert others.
- Environment blocker (NOT product): Go 1.26 quic-go panic if `GOTOOLCHAIN` unset; missing sim for TC-07.
- Scope drift (BLOCKING): any client receive-path change (that is #172); any parallel-relay scaffolding (refuted).

## Done Criteria
- [ ] RED added first, failed for the expected reason (go1.25.0).
- [ ] Each fix mutation-verified (re-add reject → contract test red).
- [ ] Relay suite + `-race` + golangci-lint green; go-mknoon suite green (go1.25.0).
- [ ] Frozen contract now pins full-inbox→OK (negative control).
- [ ] TC-07 proven on a sim (the wire leg), not a fake.
- [ ] Group + media store-when-full audited (TC-06/TC-11).
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] Operator redeploy note recorded (in-place, no parallel relay, no flag).

## Scope Guard (hard "Do not")
- Do not build a parallel/second relay or any `RELAY_PRIVATE_KEY`#2 / advertise-both / drain-telemetry scaffolding (refuted).
- Do not change the CLIENT receive/disposition path (that is #172).
- Do not re-add encrypted keys to the oversized push (recreates the FCM >4096 drop).
- Do not remove the `RejectedFull` enum/counters or the client `INBOX_FULL` parser.
- Do not pair this revert with any other breaking relay change in the same deploy.

## Accepted Differences / Intentionally Out Of Scope
- The "reject-full → online sender retries truthfully" feature is deliberately deferred to a future new-client + new-relay/protocol-ID (not kept on the live relay).
- R1 oversized-push fallback stays as-is (a backward-compatible improvement); the only R1 follow-up is the optional client drain-ignores-`preview_unavailable` defensive test.
- Parallel-relay migration mechanics are documented (Refuted section) as the contingency for a FUTURE genuinely-breaking change; not built here.

## Dependency Impact
- Independent of #172 (relay vs client). Closes the relay half of the 2026-06-28 incident's NET-REL-07 exposure.

## Reviewer Findings
<verbatim sufficiency / missing-coverage / scope-risk verdict — fill at review>

## Arbiter Decision
Structural blockers: … | Deferred details: … | Accepted differences: …

## Final Execution Verdict
Verdict: **implemented, host-green** (2026-07-02). | Files changed: go-relay-server/{backend_memory.go, backend_redis.go, limits.go} production; go-relay-server/{backend_memory_test.go NEW, backend_redis_test.go, inbox_test.go, limits_test.go, metrics_test.go, protocol_contract_test.go, server_bootstrap_test.go} + go-mknoon/integration/{local_relay_harness_test.go, relay_test.go} tests. | Tests run: relay `go test ./...` + `-race` + `-tags integration` all ok; go-mknoon full suite ok (node 445s, bridge 197s) + integration ok 93s; golangci-lint 0 issues. | Blocking: none. | QA verdict: RED-first proven (5 TCs failed exactly on the reject-at-cap contract; RED baseline = mutation proof); frozen contract now pins full-inbox→OK (TC-01). | Non-blocking follow-ups (owner): (1) **relay redeploy** — operator step, in-place, backward-compatible by construction, needs explicit prod authorization (this session's user); (2) TC-07 reliability-sim full-inbox→delivered scenario registration + run (deferred-not-waived, sim env); (3) optional TC-09/TC-10 defensive tests (plan marks not load-bearing).
