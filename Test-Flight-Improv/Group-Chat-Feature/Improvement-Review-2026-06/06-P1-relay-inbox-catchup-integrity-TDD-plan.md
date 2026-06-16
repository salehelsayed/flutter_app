> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1→ re-scoped P2/P3** · TDD plan for [finding 06](./06-P1-relay-inbox-catchup-integrity.md)

---

# 06 — Relay Inbox Catch-Up Integrity: Critical Resolution Assessment + TDD Plan

**Status: VERIFIED (13-agent verify+refute workflow, 2026-06-16) + 1st-party source byte-trace.**
**Headline: the finding is substantially RESOLVED or OVERSTATED. Its designated "land-first, highest-leverage quick win" (Improvement 3) targets a bug that does not exist. A small, defensible TDD plan remains for the genuine residuals.**

---

## 1. Resolution verdict (per improvement)

| # | Improvement | Resolution | Criticality (corrected) | Decisive evidence (CURRENT source — finding's line numbers are stale) |
|---|---|---|---|---|
| 1 | Self-describing / backend-portable cursors | **RESOLVED** | — | `mknoon-since-ms:<maxTs-1>` synthetic cursor is minted/persisted/reloaded (`drain_group_offline_inbox_use_case.dart:1046-1067, 855-866, 292`) and routed to a since-query in Go (`go-mknoon/node/group_inbox.go:447-465, 483-493`). The backend-portable resume-by-timestamp the finding asked for is already shipped. |
| 2 | Surface cap-eviction as a distinct gap (`backlogTruncated` + low-water) | **UNRESOLVED** | **Low–Medium** | No truncation concept exists. The `groupInboxCappedCounter` metric is **declared but DEAD** — `metrics.go:212` declares `relay_group_inbox_capped_total`, but it is **never `.Inc()`'d**; the group drop-oldest sites dead-assign overflow (`backend_memory.go:375-378 _ = overflow`) / silently truncate (`backend_redis.go:669-671`). Operators are blind to group cap eviction. |
| 3 | Lock the range hash byte-for-byte (alleged `id` mismatch) | **RESOLVED (bug non-existent)** | Low | **The headline claim is factually WRONG.** The gomobile bridge re-projects every group message to exactly `{from,message,timestamp}` before it reaches Dart: `GroupInboxRetrieveCursor` (`go-mknoon/bridge/bridge.go:2671-2678`) and `GroupHistoryRepairRange` (`bridge.go:2723-2730`). The node-internal `InboxMessage` carries `id` (`go-mknoon/node/inbox.go:16-19`), but **`id` never crosses the bridge**. So the Dart full-map hash already operates over `{from,message,timestamp}` and matches the relay's 3-field hash. Repair is **not** a no-op. |
| 4 | Collapse the two pagination paths | **UNRESOLVED** | Low | No unification landed (git clean). The auth-less `backend.RetrieveCursor` has **zero production callers** (test-only: `failover_test.go`, `redis_failover_integration_test.go`, `group_inbox_test.go`); production uses positional, format-agnostic `RetrieveWithCursorAuthorized` and is not buggy. Pure test-fidelity / CI-drift concern. |
| 5 | Redis per-page full-list refetch | **UNRESOLVED** | **Moot in prod** | Real (`RetrieveSince(groupId,0)` per page; prune hourly), but **Redis is not the deployed backend** (see §2) and the cost is hard-bounded by the 500-msg/group cap. Latent on the unshipped Redis rollout only. |
| 6 | Single canonical retention anchor | **UNRESOLVED** | Low | Relay anchors store-time `<=` cutoff; client drops on payload-time exclusive `isBefore` (`drain:520-525`, `group_backlog_retention_policy.dart:7-8`). Genuine but boundary-only, single-message, and the dominant "served-then-hidden" direction is the *intended* retention behavior. |

### The contradiction the workflow surfaced — and how it was settled

The verify/refute agents split on the load-bearing question: **does the relay `id` reach the Dart range-hash validation?** The Improvement-1/2 and deployment agents traced the node `InboxMessage` struct (`id,omitempty`) + Dart `Map.from` and concluded "`id` survives → repair is a guaranteed no-op." The Improvement-3 agent traced the gomobile bridge and concluded "`id` is stripped → no bug." **First-party source confirms Improvement 3:** the bridge functions at `bridge.go:2671-2678` and `:2723-2730` explicitly build `map{"from","message","timestamp"}` — there is no `id` key in the JSON returned to Dart. The other agents missed the gomobile re-projection layer sitting *between* the node struct and the Dart `Map.from`. **There is no silent-loss bug here.**

---

## 2. Deployment reality (drives the criticality corrections)

- **Deployed backend = memory (in-process), not Redis.** `server_bootstrap.go:35-54` defaults `RELAY_BACKEND` empty → `backendKindMemory`; the documented systemd unit (`go-relay-server/NOTES.md`) sets only `FIREBASE_SERVICE_ACCOUNT` — no `RELAY_BACKEND`/`REDIS_URL`. Redis is an opt-in future rollout (`Testing-Tracking/phase7-resilience-rollout.md:46-47, 95`).
- **Consequence:** on memory, a relay restart wipes the message map *and* resets `idCounter` to 0 (`backend_memory.go:319-325, 381-388`). A persisted client cursor like `"57"` becomes unfindable → `cursorFound=false` → re-deliver-from-head + a fabricated history gap. **But** Improvement 1's synthetic `mknoon-since-ms:` cursor is the mitigation and works, and — per §1.3 — the repair path it falls into is *functional* (not a no-op). So the restart hazard degrades gracefully.
- **Improvement 5 is moot in production** (Redis path). Any framing of it as a live hot-path cost is wrong on the shipped backend.

---

## 3. Does a TDD plan make sense?

**A full implementation of improvements 1–4 as written: NO.** Improvements 1 and 3 are resolved/non-existent; 4, 5, 6 are low or moot. Scoping work off the finding's proposed symbols (`encodeGroupInboxCursor`, `backlogTruncated`, `lowWaterMark`, `RetrieveCursorAuthorized`) would be chasing ghosts — none exist, and most of what they'd fix isn't broken.

**A tight plan for the genuine residuals: YES, and it is small + high-value-per-effort.** Two things are real and worth doing:
1. The range-hash parity that the entire repair safety-net depends on **works only by the luck of the bridge's id-strip contract** and has **no cross-language regression guard** — one future field added to a bridge serializer silently breaks repair. Harden it *by construction* + lock it with a golden vector.
2. The group cap-eviction counter is **dead**, so operators cannot even see whether Improvement 2's full protocol is ever needed. Wire it before deciding to build the protocol.

Everything else is explicitly deferred (§7).

---

## 4. Phase 1 — Lock range-hash parity by construction + golden vector *(P2, small)*

**Why:** today Dart's `computeGroupHistoryRangeHash` (`drain_group_offline_inbox_use_case.dart:1446-1462`) hashes the *full* canonicalized map. It only matches the relay's 3-field hash because the bridge happens to strip `id`. That coupling is invisible and untested. We remove the coupling and add the missing cross-language regression guard.

> **Client item (1A) ships without a relay deploy. The relay item (1C) is deploy-gated but guards an edge unreachable with today's payloads — ship with the next relay build.**

### 1A. Dart: project to `{from,message,timestamp}` before hashing *(client-only, no migration)* — TDD red→green
- **Red:** in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, add a test feeding `computeGroupHistoryRangeHash` a message map that contains an extra `id` key (and an unrelated extra key), and assert the result **equals** the hash of the same map with only `{from,message,timestamp}`. This **fails today** (full-map canonicalization includes `id`). This is the inverse of the existing masking fixtures that assert `id` is absent (`drain_..._test.dart:~2600`).
- **Green:** change `computeGroupHistoryRangeHash` to canonicalize an explicit projection:
  ```dart
  String computeGroupHistoryRangeHash(List<Map<String, dynamic>> messages) {
    final canonical = messages
        .map((m) => jsonEncode(<String, dynamic>{
              'from': m['from'],
              'message': m['message'],
              'timestamp': m['timestamp'],
            }))
        .join('\n');
    return sha256.convert(utf8.encode(canonical)).toString();
  }
  ```
  Keys are already alphabetical (`from < message < timestamp`), matching the relay's `map[string]interface{}` marshal (Go sorts map keys) — so no behavior change for today's id-free inputs, but now robust to any extra field the bridge might forward.
- **Gate:** existing drain suite stays green (id-free fixtures unaffected); new robustness test green.

### 1B. Cross-language golden vector *(the core deliverable; test-only both sides)*
- One shared fixture of byte-exact inputs → **one expected lowercase-hex string**, asserted in **both**:
  - Go: `go-relay-server/group_inbox_test.go` — call `computeGroupHistoryRangeHash([]groupInboxMessage{...})`.
  - Dart: `drain_group_offline_inbox_use_case_test.dart` — call `computeGroupHistoryRangeHash([...])`.
- Edge cases (each a fixture row): empty `message`; unicode; an **`id`-bearing** input that MUST NOT change the hash (locks 1A + the relay's field-set); a large `timestamp` near int64; and a `message` containing `<`, `>`, `&`, `/` (motivates 1C — see below).
- **Spec, documented in a comment block next to both implementations:** field set exactly `from,message,timestamp`; keys alphabetical; `timestamp` a bare JSON integer (Go `int64` / Dart `int`); UTF-8; messages joined with `\n`; SHA-256, lowercase hex.

### 1C. Relay: stop HTML-escaping in the range hash *(relay Go, deploy-gated; edge unreachable today)* — TDD red→green
- **Red:** the `<>&` golden-vector row fails on the **Go** side only — `json.Marshal` (`inbox.go:1176`) HTML-escapes `<`→`<`, `>`→`>`, `&`→`&`; Dart `jsonEncode` does not. (Reachable today? **No** — the hashed `message` is the encrypted group envelope: base64 ciphertext + constant enums + integers, no `<>&`. This is forward-hardening, not a live bug.)
- **Green:** marshal the per-message payload with HTML escaping disabled:
  ```go
  var buf bytes.Buffer
  enc := json.NewEncoder(&buf)
  enc.SetEscapeHTML(false)
  if err := enc.Encode(payload); err != nil { continue }
  parts = append(parts, strings.TrimRight(buf.String(), "\n"))
  ```
  in `computeGroupHistoryRangeHash` (`go-relay-server/inbox.go:1168-1184`). Now Go and Dart agree on `<>&`.
- **Gate:** `go test ./...` in `go-relay-server` green incl. the new vector; pre-existing relay group-inbox tests unchanged. Rebuild not required for the client (relay-only); ships with next relay build.

---

## 5. Phase 2 — Wire the dead group cap-eviction counter *(relay Go, deploy-gated, trivial)*

**Why:** `groupInboxCappedCounter` (`metrics.go:212`, `relay_group_inbox_capped_total`) is declared and never incremented — operators have zero visibility into group cap eviction. This is the cheap, high-value half of Improvement 2 and the prerequisite for deciding whether Phase 3 is ever worth building.

- **Red:** Go test stores `> maxMessagesPerGroup` (500) messages for one group; assert `groupInboxCappedCounter` increased by the overflow count. Cover **both** backends (memory + redis under a redis test harness if available; memory at minimum).
- **Green:**
  - `backend_memory.go:375-378` — replace `_ = overflow` with `groupInboxCappedCounter.Add(float64(overflow))` before `msgs = msgs[overflow:]`.
  - `backend_redis.go:669-671` — compute `dropped := len(values) - b.maxPerGroup` and `groupInboxCappedCounter.Add(float64(dropped))` before the slice.
- **Gate:** `go test ./...` green; metric increments observed in test.

---

## 6. Migration / collision notes

- **No relay DB migration** — relay state is in-memory (deployed) / Redis list (opt-in). Phases 1–2 touch hash computation, a test fixture, and a metric counter only.
- **Phase 1A is pure client logic** in `drain_group_offline_inbox_use_case.dart` — **no SQLite migration**, no schema change.
- **No contention with the hot 078–080 band** (held by `undecryptable-selfheal` 078, finding 03 removal-rotation deferred-distrib, finding 09 media-bounded). Finding 06's planned work does not enter the migration queue. *Only* the deferred Phase 3 (a durable client "truncated" gap flag) would need a migration — take the next free number at landing (~081+) and coordinate then.

---

## 7. Explicitly DEFERRED / NOT planned (with rationale)

| Item | Decision | Rationale |
|---|---|---|
| Improvement 1 (portable cursors) | **Done — no work** | Synthetic `mknoon-since-ms:` cursor already delivers backend-portable resume. |
| Improvement 2 **full** (`backlogTruncated` field + low-water mark + client terminal "truncated" gap state + l10n) | **DEFER** until Phase 2's counter shows real eviction volume in prod | Medium effort, low–medium value: repair is functional (§1.3), so loss only occurs for a range that is *both* cap-evicted at the relay *and* held by no online peer, in a group exceeding 500 msgs / 7 days while a member is offline. Build it only if telemetry proves it bites. Needs a DB migration (~081+) if the terminal state is persisted. |
| Improvement 4 (collapse pagination paths) | **SKIP** (optional CI-fidelity note) | Auth-less backend path has zero prod callers; production path is correct. Test-only drift, not a correctness/security bug. If desired, parametrize the failover/group-inbox cursor tests over the production `RetrieveWithCursorAuthorized` so they exercise the shipped path. |
| Improvement 5 (Redis prune-on-read / sorted set) | **SKIP** | Moot — Redis not deployed; cost bounded by the 500-msg cap. Revisit only if/when the Redis backend ships. |
| Improvement 6 (canonical retention anchor) | **SKIP** (optional boundary test) | Boundary-only, single-message, dominant direction is intended retention behavior. At most add a Dart boundary test asserting a message within the relay TTL window is not client-side-expired. |

---

## 8. Test & verification strategy (summary)

- **Unit (Dart):** `drain_group_offline_inbox_use_case_test.dart` — 1A robustness test (id/extra-key invariance) + 1B Dart half of the golden vector.
- **Unit (Go):** `go-relay-server/group_inbox_test.go` — 1B Go half of the golden vector (incl. `<>&` row that drives 1C) + Phase 2 counter-increment test.
- **Cross-language golden vector** is the headline regression guard: identical bytes → identical hex on both sides; tie it to a blocking gate since it protects the entire gap-repair safety net from future drift.
- **No integration-harness or device-matrix work required** for the planned scope (Phases 1–2 are unit-level). Device verification would only be warranted if Phase 3 (`backlogTruncated` UX) is later built.

---

## 9. Rollout order

1. **Phase 1A** (Dart projection hardening + its red test) — ships in the Flutter client, no relay deploy. *Highest priority: removes the invisible bridge-contract coupling.*
2. **Phase 1B** (golden vector, both sides) — lands with 1A on the Dart side and with the relay change on the Go side.
3. **Phase 1C** (relay `SetEscapeHTML(false)`) + **Phase 2** (counter wiring) — bundle into the next relay Go build + EC2 deploy (memory backend; single-host restart-in-place).
4. Re-evaluate Phase 3 after the counter reports from prod.
