> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · [Findings appendix](./appendix-findings.md)

---

# Guarantee complete, ordered offline catch-up across relay lifecycle

**Priority: P1** · Theme: relay group-inbox catch-up reliability · Workstream: Group-Chat-Feature

> One-liner: Make cursors backend-portable, surface cap-eviction as an explicit gap, lock the range-hash byte-for-byte, and collapse the two divergent pagination paths.

---

## Why this matters (user experience)

The group-inbox relay is the store-and-forward backstop that lets a member who was offline (app closed, no peers, bad network) catch up on everything they missed. When that catch-up is incomplete or mis-ordered, the conversation **diverges silently across members** — different people see different message sets, and nobody is told.

Three lifecycle events break catch-up today:

- **Relay restart / backend swap.** A resuming client presents an opaque cursor the new backend cannot match, so pagination restarts from the head. Best case the member re-downloads and re-processes the entire backlog (slow, jittery catch-up); worst case, combined with eviction, a block of history is skipped.
- **Cap eviction.** A member offline during a busy period (or in a chatty group exceeding 500 stored messages in 7 days) permanently loses the oldest messages. The relay cannot distinguish that capacity loss from a normal peer-recoverable gap, and may surface no signal at all if no authorized page comes back.
- **Range-hash divergence.** History-gap repair — the safety net that fills holes — fails closed today because the Go relay and Dart client hash *different field sets*. Every relay-sourced repair range with a populated `id` deterministically fails `range_hash_mismatch`, so the gap persists forever with no user-visible recovery.

The byte-for-byte range-hash fix (improvement 3) is a small, high-leverage change that protects the entire gap-repair safety net the other improvements depend on.

---

## Current behaviour & evidence

### Cursor IDs are ephemeral and not backend-portable
- Memory backend assigns IDs from an in-process counter that **resets to 0 on restart** and is never seeded from existing data: `go-relay-server/backend_memory.go:313` (`idCounter` field), `:318-324` (`newMemoryGroupInboxBackend` starts at zero), `:372-377` (`b.idCounter++`, `ID: fmt.Sprintf("%d", b.idCounter)`).
- Redis backend assigns from a **global `INCR ginbox:idseq`**: `go-relay-server/backend_redis.go:560-562` (`sequenceKey`), `:626-635`.
- The raw ID is handed to clients verbatim as the cursor: `go-relay-server/inbox.go:1041` (`nextCursor = result[...].ID`), serialized via the `id` json field at `inbox.go:807`.
- On an unknown cursor, both production and backend paths reset `startIdx=0` / `cursorFound=false`: `inbox.go:1009-1017` (authorized path), `backend_memory.go:427-430`, `backend_redis.go:715-717`.
- The only timestamp-based fallback is the **synthetic since-cursor** (`mknoon-since-ms:` prefix, `go-mknoon/node/group_inbox.go:17,446,482-491`) — it fires only on that literal prefix, never on a stale opaque numeric cursor.

### Cap eviction is silent and orphans cursors
- `maxMessagesPerGroup = 500`, TTL 7 days: `go-relay-server/inbox.go:30-31`.
- Memory drops oldest via `msgs[overflow:]` with no record: `backend_memory.go:366-370`. Redis drops via `values[len-maxPerGroup:]`: `backend_redis.go:645-647`.
- A cursor pointing at an evicted ID yields `cursorFound=false`. The history-gap detector fires only when `cursor != "" && !cursorFound && len(repairMessages) > 0`: `inbox.go:1090-1098`. So when an authorized page **is** returned a gap is emitted (`inbox.go:1047`) — but it is indistinguishable from a peer-recoverable gap, and when no authorized page comes back **no gap fires at all** (`inbox.go:1034-1036`). There is no `lowWaterMark` / `backlogTruncated` concept anywhere in the subsystem.

### Range-hash is not byte-identical across languages
- Relay hashes **only `{from, message, timestamp}`** per message, marshaled with `json.Marshal`, joined with `\n`: `go-relay-server/inbox.go:1139-1154`.
- The wire message the client receives **includes `id`**: `groupInboxMessage` serializes `from/message/timestamp/id,omitempty` (`inbox.go:803-808`; `RecipientPeerIds` is `json:"-"`), and `go-mknoon/node/inbox.go:16-19` re-serializes `{id,from,message,timestamp}`.
- Client hashes the **full message map** (recursive key-sort + `jsonEncode`), thereby including the `id` key the relay omits: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:1446-1450`.
- Validation fails closed — requires `result.rangeHash == gap.expectedRangeHash && computedHash == gap.expectedRangeHash`: `drain_group_offline_inbox_use_case.dart:1324-1325`. Existing Dart tests build fixtures with only `{from,message[,timestamp]}` so they are self-consistent in Dart and never catch the cross-language `id` mismatch.

### Two divergent pagination implementations
- Production stream (`group_retrieve_cursor`) calls `RetrieveWithCursorAuthorized` (`inbox.go:1503`), which does `backend.RetrieveSince(groupId, 0)` (`inbox.go:1006`) + store-layer pagination/gap logic (`inbox.go:1006-1047`).
- The backend's own `RetrieveCursor` (Redis-transaction-aware, gap-emitting) at `backend_memory.go:407-458` and `backend_redis.go:686-746` is reached **only** via `RetrieveWithCursor` (`inbox.go:990-994`), used by `failover_test.go:231-252` and `redis_failover_integration_test.go:238` — never by `HandleInboxStream`.

### Redis read paths re-fetch the whole list per page
- `RetrieveSince` does a plain `LRange(0, -1)` and filters in memory, never writing back the pruned list: `backend_redis.go:660-684`. The authorized cursor path calls it for **every page** (`inbox.go:1006`), making catch-up O(pages × total). Prune runs only hourly.

### TTL anchor mismatch (low-severity edge)
- Relay TTL is anchored on **store time** (`Timestamp = time.Now().UnixMilli()` at store, `backend_memory.go:376` / `backend_redis.go:634`; filter `timestamp <= now-ttl`, strict `<=`). Client retention is anchored on the **payload timestamp** (`drain_group_offline_inbox_use_case.dart:520`, cutoff built at `:289`) against `groupBacklogRetentionCutoff` (`lib/features/groups/domain/models/group_backlog_retention_policy.dart:7-8`, computed from the 7-day `groupBacklogRetentionWindow` at lines 1/3-4, via `isBefore`). Same window, different anchors and comparators → boundary messages can be served-then-hidden or pruned-then-missing.

---

## Root cause(s)

1. **Cursor identity is coupled to ephemeral sequence allocation** (per-process counter / global INCR) instead of a stable, self-describing key (timestamp + messageId). "Cursor not found" is treated as "start over" rather than "resume by time."
2. **No retention low-water mark.** The store remembers what it has, never what it *dropped*, so it cannot tell a client that older history is gone for good vs. recoverable from peers.
3. **No canonical serialization contract for the range hash.** Two independent implementations (Go map-marshal vs. Dart canonicalize-full-map) over two different field sets, with no shared golden vector to keep them honest.
4. **Pagination logic was forked.** The ACL filter lives in the store layer, forcing a `RetrieveSince(0)`-then-paginate pattern that bypasses the backend's purpose-built cursor method, leaving two paths free to drift and an O(N×total) re-fetch.
5. **Two retention clocks** (store-time vs payload-time) with no single canonical anchor.

---

## Proposed improvements

> Ordered roughly by leverage-per-effort. Improvement 3 is the quick win and should land first.

### 1. Make cursors self-describing and backend-portable *(high / medium)*

**Goal:** a cursor survives relay restart, memory↔Redis swap, and key recreation, and degrades to a timestamp-resume instead of a head-restart.

- Change the cursor from a raw ID to a **composite token** `"<timestamp>:<id>"` (or a base64url-encoded `{ts,id}` blob). Keep it opaque to the client.
  - New helpers in `go-relay-server/inbox.go`: `encodeGroupInboxCursor(ts int64, id string) string` and `decodeGroupInboxCursor(cursor string) (ts int64, id string, ok bool)`. Accept a **bare legacy numeric cursor** (no `:`) as `id`-only with `ts=0` for backward compatibility during rollout.
- In the single authorized cursor method (see improvement 4), resolve `startIdx` as:
  1. Exact `id` match (current behavior) → resume after it.
  2. If `id` not found **and** `ts > 0` → resume at the **first message with `Timestamp > ts`** (timestamp-based resume). This recovers continuation across an ID-space reset.
  3. If neither matches → only then fall back to head, and emit the appropriate gap/truncation signal (improvement 2).
- Set `nextCursor = encodeGroupInboxCursor(last.Timestamp, last.ID)` at the emit sites (`inbox.go:1041`, and the backend `nextCursor` lines `backend_memory.go:443/451`, `backend_redis.go:740`).
- **Seed the memory counter on load** so restarts in a long-lived process do not collide: in `newMemoryGroupInboxBackend` (and on first `Store` for a group), set `idCounter = max(existing IDs)`. (Memory data does not survive process exit, but this protects test harnesses and any future memory persistence; the real cross-restart safety comes from the timestamp resume above.)

**Wire impact:** cursor string format changes but stays opaque; the legacy-numeric acceptance path means in-flight clients with old cursors keep working (they hit the timestamp/id resolution). No DB/migration impact (relay is in-memory or Redis-list).

### 2. Surface cap-eviction as an explicit, distinct gap *(medium / medium)*

**Goal:** a client whose cursor predates the oldest retained message is told "older messages may be unavailable" rather than silently restarting or mis-classifying a capacity gap as peer-recoverable.

- Track a **per-group low-water mark** = oldest retained `{id, timestamp}`. Memory: derive from `msgs[0]` after prune/eviction. Redis: store alongside the list (e.g. `ginbox:lowwater:<group>` updated inside the `StoreWithRecipients` WATCH txn at `backend_redis.go:645-648`, or derive from `decoded[0]` on read).
- Add a new field to `groupInboxHistoryGap` (`inbox.go:811-818`):
  ```go
  BacklogTruncated bool `json:"backlogTruncated,omitempty"`
  ```
- In `buildGroupInboxHistoryGaps` (`inbox.go:1090-1098`): when the presented cursor's resolved timestamp/id is **older than the low-water mark**, set `BacklogTruncated: true`. Also emit a truncation gap when `cursorFound=false` and there is no recoverable head, so the "no authorized page returned → no gap" hole (`inbox.go:1034-1036`) is closed.
- Emit an operator signal on eviction: increment a new `groupInboxEvictedCounter` and log at the drop sites (`backend_memory.go:366-370`, `backend_redis.go:645-647`) so groups outrunning the cap are detectable.
- Make `maxMessagesPerGroup` (`inbox.go:30`) configurable via the relay config/env so busy deployments can raise it.
- **Client:** in `drain_group_offline_inbox_use_case.dart`, when a gap carries `backlogTruncated`, mark the gap state distinctly (e.g. `truncated` rather than `failed`) and surface a one-time "some older messages may be unavailable" notice instead of looping repair attempts that can never succeed. New localization keys in `lib/l10n/app_en.arb` (+ `ar`/`de`).

**Wire impact:** additive `backlogTruncated` field (omitempty, backward compatible). No migration.

### 3. Lock the range hash byte-for-byte (quick win, land first) *(high / small)*

**Goal:** Go relay and Dart client compute *identical* hex over *identical* bytes, so gap repair stops failing closed.

- **Define one canonical spec** (document it in a comment block next to both implementations):
  - Field set: exactly `from`, `message`, `timestamp` — **no `id`, no recipients**.
  - Per-message JSON: keys in fixed order `from, message, timestamp`; `timestamp` as an integer (no float, no quotes); UTF-8; messages joined with `\n`; SHA-256, lowercase hex.
- **Client fix (`drain_group_offline_inbox_use_case.dart:1446-1450`):** hash the reduced projection, not the full map:
  ```dart
  String computeGroupHistoryRangeHash(List<Map<String, dynamic>> messages) {
    final canonical = messages.map((m) => jsonEncode({
      'from': m['from'],
      'message': m['message'],
      'timestamp': m['timestamp'],
    })).join('\n');
    return sha256.convert(utf8.encode(canonical)).toString();
  }
  ```
  (Replaces the `_canonicalizeJson(fullMap)` path that pulls in `id`.) Ensure `timestamp` is an `int`, matching Go's `int64` marshal.
- **Relay:** keep `computeGroupHistoryRangeHash` (`inbox.go:1139-1154`) but make the field order explicit and guaranteed (Go map-marshal already sorts keys, but pin it with an ordered struct/`json.RawMessage` to remove any escaping/number ambiguity).
- **Golden-vector test (the core deliverable):** a fixture of byte-exact inputs with one expected hex string, asserted by **both** a Go test (`go-relay-server/group_inbox_test.go`) and a Dart test (`drain_group_offline_inbox_use_case_test.dart`). Include edge cases: empty message, unicode, characters Go/Dart escape differently (`<`, `>`, `&`, `/`, control chars), large `timestamp` near int64 range, and a populated-`id` message (which must **not** change the hash). This is the regression guard that keeps the two languages from drifting again.

**Wire impact:** none (hash output stabilizes; field set unchanged on the relay). The client change is the corrective one.

### 4. Collapse the two pagination paths *(medium / large)*

**Goal:** production and tests exercise the *same* cursor/gap code; fix bugs/TTL/cap once.

- Add an authorized variant to the `GroupInboxBackend` interface so the ACL filter lives in the backend:
  ```go
  RetrieveCursorAuthorized(groupId, cursor string, limit int, requesterPeerId string)
      ([]groupInboxMessage, string, []groupInboxHistoryGap)
  ```
  Implement in both backends by folding `groupInboxMessageAuthorizedForPeer` into the existing `RetrieveCursor` scans (`backend_memory.go:407-458`, `backend_redis.go:686-746`).
- `RetrieveWithCursorAuthorized` (`inbox.go:996-1047`) becomes a thin wrapper that calls `backend.RetrieveCursorAuthorized` — deleting the `RetrieveSince(0)`-then-paginate-in-store block (`inbox.go:1006-1047`). This also kills the per-page full-list re-fetch.
- Both backends then share identical pagination/gap semantics validated by the same tests the production path uses.

**Note:** this is the right home for the cursor-resume (improvement 1) and low-water-mark (improvement 2) logic — do it after 1–3 so there is a single place to land them.

### 5. Opportunistic Redis prune-on-read + sorted-set option *(medium / large, optional / follow-up)*

- Short term: in `RetrieveSince` (`backend_redis.go:660-684`) and `Stats`, when expired entries are detected, write back the pruned list (reuse the `redisReplaceList` + `normalizeRedisGroupInboxRecords` path already used in `StoreWithRecipients`).
- Long term: store group messages in a **Redis sorted set** keyed by ID/timestamp so cursor pagination uses `ZRANGEBYSCORE`/`ZRANGEBYLEX` (O(log N + page)) and TTL pruning uses `ZREMRANGEBYSCORE`, eliminating the LRANGE-the-world-per-page cost. This pairs naturally with improvement 4 (backend returns just the page).

### 6. Single canonical retention anchor *(low / medium, optional / follow-up)*

- Pick one anchor. Recommended: client retention filters on the **relay-provided store timestamp** (`msg['timestamp']`) consistently in `drain_group_offline_inbox_use_case.dart:520` (cutoff at `:289`), matching the relay's `<=` TTL semantics. Add a boundary test (a message within the relay window must never be classified expired client-side) or a small grace band.

---

## Affected files & components

| Area | File | Improvements |
|------|------|--------------|
| Relay cursor encoding / authorized retrieval / gaps / range hash | `go-relay-server/inbox.go` | 1, 2, 3, 4 |
| Memory backend (counter seed, eviction signal, authorized cursor, low-water) | `go-relay-server/backend_memory.go` | 1, 2, 4 |
| Redis backend (authorized cursor, low-water, prune-on-read, eviction signal) | `go-relay-server/backend_redis.go` | 1, 2, 4, 5 |
| Group inbox store / interface | `go-relay-server/group_inbox_store.go` | 4 |
| Relay backend interface decl | `go-relay-server/inbox.go` (interface) | 4 |
| Node cursor passthrough / synthetic since fallback | `go-mknoon/node/group_inbox.go` | 1, 2 |
| Client drain: range-hash projection, truncation handling, retention anchor | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` | 2, 3, 6 |
| Retention policy | `lib/features/groups/domain/models/group_backlog_retention_policy.dart` | 6 |
| Localization (truncation notice) | `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb` (+ generated) | 2 |
| Relay config (configurable cap) | relay config/env wiring | 2 |
| Tests | `go-relay-server/group_inbox_test.go`, `failover_test.go`, `redis_failover_integration_test.go`, `drain_group_offline_inbox_use_case_test.dart` | 1–4 |

---

## Test & verification strategy

### Unit
- **Go (`group_inbox_test.go`):**
  - Cursor portability: store N messages, present a stale numeric cursor and a composite cursor whose `id` no longer exists but `ts` does → assert timestamp-resume returns the correct continuation, not head-restart. Simulate a memory backend "restart" (fresh backend, counter at 0) and assert no skip/replay.
  - Cap eviction: overflow past 500, then retrieve with a cursor older than the low-water mark → assert `backlogTruncated=true` gap and eviction counter incremented.
  - Path collapse: parametrize the existing cursor/gap tests over the *production* method so `failover_test.go` and `HandleInboxStream` share assertions.
- **Dart (`drain_group_offline_inbox_use_case_test.dart`):**
  - Range hash projects only `{from,message,timestamp}`; a message with a populated `id` produces the same hash as one without.
  - A `backlogTruncated` gap transitions to a `truncated` state (not infinite-retry `failed`) and surfaces the notice.
- **Cross-language golden vector (the headline test):** a shared fixture (byte-exact inputs → one expected hex) asserted in **both** the Go test and the Dart test. Without this, improvement 3 has no regression guard.

### Integration harness
- Extend the existing group recovery harness `integration_test/group_recovery_e2e_test.dart` and the multi-device harnesses (`integration_test/group_multi_device_real_harness.dart`, `group_multi_party_device_real_harness.dart`) with:
  - **Relay-restart catch-up:** member offline → relay restarts (memory backend) → member resumes; assert the full, ordered backlog with no duplicates and no skips.
  - **Cap-eviction catch-up:** push the group past 500 while a member is offline → resume; assert a `backlogTruncated` notice appears and the recoverable tail is delivered intact.
  - **Gap-repair round-trip:** induce a real cursor-outran-backlog gap and assert the relay-sourced repair range now passes `range_hash` validation end-to-end (the bug improvement 3 fixes).

### Device matrix & gates
- Run on the established device pair (iPhone13 `00008110-...`, Pixel6 `21071FDF600CSC`) per `memory/project_physical_device_testing.md`.
- Update `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and `Test-Flight-Improv/test-gate-definitions.md` with new gates: "relay-restart catch-up completeness," "cap-eviction truncation notice," and "cross-language range-hash parity." Tie the range-hash golden vector to a blocking gate since it guards the entire repair safety net.

---

## Risks, trade-offs & rollout

| Risk | Mitigation |
|------|-----------|
| Cursor format change breaks in-flight clients | Accept bare-numeric legacy cursors (`ts=0`, id-only) during a deprecation window; resolve by id first, then timestamp. Land relay before requiring new format. |
| Range-hash change invalidates already-pending gaps | The current hash is *already failing* in production, so pending gaps are stuck regardless. After the fix, re-issuing the gap (new `expectedRangeHash`) heals them; add a one-time client re-derive on first post-update drain. |
| Timestamp-collision (two messages same ms) makes `ts`-only resume ambiguous | Composite `ts:id` disambiguates; timestamp-resume picks `Timestamp > ts` and the id tiebreak removes the boundary message correctly. |
| Path collapse (improvement 4) is large and touches the hot read path | Land behind the new shared tests; keep `RetrieveWithCursor` as a thin alias during transition; ship 1–3 independently first. |
| Low-water mark adds Redis state | Derive from `decoded[0]` on read (no extra key) as the minimal version; only add a dedicated key if read-derive is too costly. |
| Configurable cap could let groups grow unbounded | Keep a hard upper ceiling; the config only raises within bounds, and the eviction metric flags runaway groups. |

**Rollout order:** (3) range-hash + golden vector → (1) portable cursors → (2) cap-eviction signal → (4) path collapse → (5)/(6) follow-ups. (3) is independently shippable and unblocks the repair safety net immediately. Relay changes ship before any client change that requires them; all new wire fields are additive/omitempty.

---

## Effort estimate

| Improvement | Effort | Notes |
|-------------|--------|-------|
| 3. Lock range hash + golden vector | **Small** | Quick win; land first. Client projection + 2 cross-lang tests. |
| 1. Portable / self-describing cursors | **Medium** | Encode/decode + timestamp-resume + counter seed + legacy acceptance. |
| 2. Cap-eviction explicit gap | **Medium** | Low-water mark, new gap field, client state + notice + l10n, config + metric. |
| 4. Collapse pagination paths | **Large** | Interface change across both backends + store + production wrapper; best done with 1–2 folded in. |
| 5. Redis prune-on-read / sorted set | **Large** | Optional follow-up; sorted-set migration is the big piece. |
| 6. Canonical retention anchor | **Medium** | Optional; low-severity edge fix + boundary test. |

**Core P1 scope (improvements 1–4): ~Medium–Large overall**, with improvement 3 delivering disproportionate safety-net value for small effort.
