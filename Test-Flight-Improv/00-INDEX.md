# Test-Flight-1 Improvement Reports

Generated: 2026-03-26

**Closure note:** Sessions `1` through `23` from `15-session-todo-roadmap.md` and `16-session-todo-roadmap-2.md` have now been planned/executed/closed. Reports `01` through `14` remain the rationale archive. The current closure state lives in Sections `8` and `9` below.

---

## 1. Test Coverage

| Report | Focus |
|--------|-------|
| [01-unit-test-coverage.md](01-unit-test-coverage.md) | Corrected module-by-module unit test picture — broad coverage, narrower remaining gaps |
| [02-integration-test-coverage.md](02-integration-test-coverage.md) | Cross-feature flows, integration quality, and remaining boundary gaps |

**Top finding:** Test coverage is materially stronger than the first pass suggested. Posts, Introduction, Groups, StartupRouter, and several cross-feature flows already have substantial coverage. The highest-value remaining gaps are notification adapter boundaries, nearby-post presence rejection logic, and one end-to-end onboarding happy path.

---

## 2. Smoke Tests

| Report | Focus |
|--------|-------|
| [03-smoke-test-strategy.md](03-smoke-test-strategy.md) | Lean smoke strategy plus change-based regression gates for high-blast-radius subsystems |

**Top finding:** The smallest effective smoke suite is already mostly present in the repo. Reusing existing startup, loading, QR, inbox, posts, and group-smoke tests is better than building a fake-only parallel test app, but smoke alone is not enough for risky shared pipelines such as 1:1 reliability.

---

## 3. Performance

| Report | Focus |
|--------|-------|
| [04-ui-performance.md](04-ui-performance.md) | Profile-gated UI/perf candidates; stale false positives removed |
| [05-database-storage-performance.md](05-database-storage-performance.md) | High-confidence DB/storage cleanups; broad indexing/caching recommendations narrowed |

**Top findings:**
- `OrbitWired` already disposes its controllers/subscriptions — that earlier P0 is stale
- Hot-path `PRAGMA table_info(...)` calls in posts helpers are real and worth fixing
- Identity loading repeats secure-storage reads across multiple screens
- Blanket index additions, message-order SQL rewrites, and heavy SQL/materialized-view work are not yet justified

---

## 4. Dead Code

| Report | Focus |
|--------|-------|
| [06-dead-code-lib.md](06-dead-code-lib.md) | Conservative dead-code review — only a small subset looks safely removable now |
| [07-dead-code-deps-config.md](07-dead-code-deps-config.md) | Dependency/config cleanup — confirmed unused package plus low-value optional script cleanup |

**Top finding:** The project is clean, but the earlier “24 files safe to remove” claim is too broad. The one easy confirmed cleanup is `cupertino_icons`; file deletion should be conservative because several candidates are still test- or smoke-backed.

---

## 5. Network Component

| Report | Focus |
|--------|-------|
| [08-network-1to1-messaging.md](08-network-1to1-messaging.md) | 1:1 send/receive/media/voice reliability with corrected durability and read-state findings |
| [09-network-group-messaging.md](09-network-group-messaging.md) | Group/announcement architecture for current scale; stale “missing retry” claims removed |
| [10-network-measurement-strategy.md](10-network-measurement-strategy.md) | Incremental observability plan — local counters/timers first, export stack deferred |

**Top findings:**
- The main concrete 1:1 reliability gap is that inline feed replies do not use the same durable pre-persist send path as the conversation screen
- Shared 1:1 delivery changes should trigger a named regression gate that covers text, media, voice, retry, and offline/recovery paths
- Group media retry/recovery already exists; it is not a missing P0 feature
- Announcement coverage is stronger than earlier reported inside the Flutter tree
- Measurement should start with local timing counters around send/retry/discovery/media, not a full metrics collector/exporter/dashboard stack

---

## 6. Use Case Audits (1:1 / Discussions / Announcements)

| Report | Focus |
|--------|-------|
| [12-1to1-chat-use-case-audit.md](12-1to1-chat-use-case-audit.md) | Core 1:1 flows are tested; remaining gaps are product features and one durability inconsistency |
| [11-group-discussion-use-case-audit.md](11-group-discussion-use-case-audit.md) | Core group lifecycle/message/recovery flows are tested; stale gap claims removed |
| [13-announcement-use-case-audit.md](13-announcement-use-case-audit.md) | Announcement enforcement is well covered in Flutter; Go-side writer enforcement remains outside this tree |
| [18-group-discussion-reliability-audit.md](18-group-discussion-reliability-audit.md) | Lean reliability-gap review: what group chat still needs to feel as trustworthy as 1:1 without overengineering |

**Top findings:**
- **1:1 Chat:** Core implemented flows are tested; the highest-value correctness gap is durable send-path parity between conversation and feed inline reply
- **Group Discussions:** Core use cases/listeners are well tested; missing items are mostly intentional product scope, not correctness failures
- **Group Discussion Reliability:** The core architecture is already solid; the main remaining reliability work is media/voice failed-send retry parity, early parent-row persistence for ordinary media, and explicit sequential send behavior so “send then lock the phone” remains trustworthy
- **Announcements:** Admin-only send and member reactions are already well covered in Flutter tests; the main remaining gap is explicit Go-side enforcement verification in the Go repo
- **QA type:** Still defined in the enum/schema but filtered out of creation UI — placeholder only

---

## 7. Regression Strategy

| Report | Focus |
|--------|-------|
| [14-regression-test-strategy.md](14-regression-test-strategy.md) | Practical regression model: baseline gate, subsystem gates, missing regressions to add, and run rules for new work |

**Top finding:** The repo already has most of the needed tests. The missing piece is a clear run strategy: small baseline on every PR, change-based subsystem gates for risky shared code, explicit file lists per gate, a bulk-classification policy for non-gate tests, and one permanent regression test for every escaped bug.

---

## 8. Session Roadmaps And Closure

| Report | Focus |
|--------|-------|
| [15-session-todo-roadmap.md](15-session-todo-roadmap.md) | Historical execution backlog for Sessions `1` through `11` |
| [16-session-todo-roadmap-2.md](16-session-todo-roadmap-2.md) | Historical follow-on backlog for Sessions `12` through `23`, including profile/evidence-gated and cross-tree work |
| [17-roadmap-closure-audit.md](17-roadmap-closure-audit.md) | Post-execution closure audit and current reading order for the folder |

**Top finding:** The folder has now moved from backlog mode into closure mode. Roadmaps `15` and `16` served as the execution backlogs through Session `23`; the closure audit now describes what is historical rationale, what remains open, and what should only be reopened if a real residual gap appears.

---

## 9. Post-Execution State

| Status | Item | Why It Still Matters | Report |
|--------|------|----------------------|--------|
| Maintain | Keep `test-gate-definitions.md` and named gates canonical | Future changes should continue to use the same gate language and command surface | 14 / 15 / 16 |
| Follow up only if needed | Complete external CI / release owner wiring for Session `12` if the local handoff artifact is still the final state | This is the only clearly externalized closure item | 16 |
| Residual only | Reopen a roadmap item only if a real regression, failed gate, or newly proven gap appears | Avoids restarting broad cleanup work without evidence | 17 |
| Intentionally deferred | Product-scope items such as read receipts, typing indicators, search, exporter/dashboard work | These were deferred by design, not missed correctness work | 08 / 09 / 10 |
| Do not reopen by default | Broad SQL/index/caching work, mass dead-code cleanup, or exporter architecture | These remain unjustified without new evidence | 05 / 06 / 10 |
