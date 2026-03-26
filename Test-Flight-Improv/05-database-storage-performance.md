# Database & Storage Performance Analysis

## Summary

7 issues remain after correcting stale or overbroad recommendations: **2 HIGH**, **3 MEDIUM**, **2 LOW**. The strongest current opportunities are hot-path schema introspection cleanup and a small identity cache. Blanket indexing, SQL rewrites, and broad caching layers are not justified yet.

---

## HIGH SEVERITY

### 1. PRAGMA introspection still runs on hot paths
**Files:** `posts_db_helpers.dart`, `post_passes_db_helpers.dart`, `post_recipients_db_helpers.dart`

- `dbInsertPost()` still checks schema columns dynamically
- `_sharedToCountExpression()` / `_sharedToBaselineExpression()` still do runtime schema inspection
- Similar capability checks exist in post-pass and post-recipient helpers
- This is a real overhead source and an implementation-ready cleanup

**Fix:** Cache schema capabilities once per opened DB and reuse them across helper calls.

---

### 2. Repeated single-post loads amplify expensive post query work
**Files:** `posts_db_helpers.dart`, `load_pinned_posts_use_case.dart`

- The heavy post load query is not run “once per post in the feed” as the earlier report implied
- It **does** become expensive when called repeatedly for one-by-one post hydration flows such as pinned-post loading
- This is a narrower, more accurate bottleneck than “materialized view now”

**Fix:** Reduce repeated `getPost()`/single-post fetch loops before introducing heavier SQL architecture.

---

## MEDIUM SEVERITY

### 3. Some targeted recovery/download indexes may help later
**Files:** `messages_db_helpers.dart`, `media_attachments_db_helpers.dart`

- The earlier report overstated missing-index coverage; several FK and core indexes already exist
- Two remaining candidates still look plausible **after profiling**:
  - `messages(status, is_incoming, timestamp)`
  - `media_attachments(download_status)`
- These paths appear bounded/occasional today, so they are not immediate P0 work

**Fix:** Add only if profiling or real-device behavior shows recovery/download scans matter.

---

### 4. Identity loading repeats secure-storage reads across screens
**File:** `identity_repository_impl.dart`

- `loadIdentity()` still does one DB read plus three secure-storage reads per call
- Multiple screens call it during initialization
- This is a small, high-confidence cache opportunity

**Fix:** Add an in-memory identity cache invalidated on `saveIdentity()`.

---

### 5. Reload-after-update pattern still adds avoidable DB reads
**File:** `message_repository_impl.dart`

- After some status updates, the repository reloads the row to rebroadcast it
- This is real, but secondary to the PRAGMA cleanup and identity cache

**Fix:** Revisit only after the higher-confidence wins are done.

---

## LOW SEVERITY

### 6. Thread-summary SQL is not the first query to optimize
**File:** `messages_db_helpers.dart`

- The thread-summary query is complex, but the main feed path still loads full histories per contact/group
- Optimizing this query before the feed read path is a poor sequencing choice

**Fix:** Defer until broader feed/read-path behavior is simplified or proven hot.

### 7. Broad query caches and bulk secure-storage APIs are premature
**Project-wide**

- The earlier report proposed project-wide query-cache decorators, TTL caches, and bulk secure-storage APIs
- Current evidence does not justify that architectural complexity

**Fix:** Do not build generic caching layers yet.

---

## Existing Index Coverage Already Present

- `media_attachments(message_id)`
- `post_comments(post_id)`
- `post_reactions(post_id)`
- `post_passes(post_id)`
- `post_recipients(post_id)` and owner indexes
- `messages(contact_peer_id)` and unread-oriented indexes

The earlier “add FK indexes everywhere” recommendation was too broad.

---

## Priority Fix Order

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | Remove hot-path PRAGMA introspection via schema-capability caching | 1-2 hours | Clear, low-risk reduction in posts helper overhead |
| **P0** | Add in-memory identity cache | 1 hour | Removes repeated secure-storage reads across screens |
| **P1** | Reduce repeated single-post lookups before heavier SQL work | 1-2 hours | Likely better payoff than materialized-view work |
| **P2** | Profile targeted recovery/download indexes | 1 hour + measurement | Only add indexes that prove useful |
| **P2** | Revisit reload-after-update broadcasts | 1 hour | Secondary DB/read reduction |
| **P3** | Defer thread-summary SQL rewrites and broad cache layers | — | Avoids premature complexity |
