# Test-Flight-1 Improvement Reports

Generated: 2026-03-27

**Closure note:** Sessions `1` through `29` have now been planned/executed/closed. Roadmaps `15` and `16` plus the residual reliability/measurement sessions `24` through `29` are historical execution artifacts. Reports `01` through `14` remain the rationale archive. The current closure state lives in Sections `8`, `9`, and `10` below.

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
- The narrow DB/storage fixes worth doing were helper-local schema-capability caching, the small identity cache, the pinned-post single-load reduction, and the reload-after-update cleanup
- Targeted index work remains evidence-only; no broad SQL/index/caching program should be reopened without new profiling
- Blanket index additions, message-order SQL rewrites, and heavy SQL/materialized-view work are still not justified by default

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
- 1:1 durable send-path parity between conversation and feed inline reply is now landed in the current Flutter tree
- Shared 1:1 delivery changes now have a named regression gate plus feed-surface companion direct coverage
- Group media retry/recovery already exists; it is not a missing P0 feature
- Announcement coverage is stronger than earlier reported inside the Flutter tree
- Lean local timing/counter coverage for the highest-value messaging gaps is now landed; exporter/dashboard work remains deferred

---

## 6. Use Case Audits (1:1 / Discussions / Announcements)

| Report | Focus |
|--------|-------|
| [12-1to1-chat-use-case-audit.md](12-1to1-chat-use-case-audit.md) | Core 1:1 flows are tested; remaining gaps are product features and one durability inconsistency |
| [11-group-discussion-use-case-audit.md](11-group-discussion-use-case-audit.md) | Core group lifecycle/message/recovery flows are tested; stale gap claims removed |
| [13-announcement-use-case-audit.md](13-announcement-use-case-audit.md) | Announcement enforcement is well covered in Flutter; Go-side writer enforcement remains outside this tree |
| [18-group-discussion-reliability-audit.md](18-group-discussion-reliability-audit.md) | Lean reliability-gap review: what group chat still needs to feel as trustworthy as 1:1 without overengineering |

**Top findings:**
- **1:1 Chat:** Core implemented flows are tested; the earlier feed-inline durable-send gap is now closed, and the remaining gaps are mostly product features plus small residual edge-case/semantics work
- **Group Discussions:** Core use cases/listeners are well tested; missing items are mostly intentional product scope, not correctness failures
- **Group Discussion Reliability:** Final acceptance revalidation confirms ordinary-media parent-row durability, ordinary-media failed-send retry parity, and explicit one-thread send serialization are landed; voice publish-failure retry remains only a narrower producer-side residual if reopened later
- **Announcements:** Session `28` revalidated that shared group reliability work did not regress announcement auth/send/recovery/read-only behavior; remaining gaps are now narrower evidence niceties, not a new reliability program
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
| [session-24-plan.md](session-24-plan.md) | Historical residual reliability implementation session |
| [session-25-plan.md](session-25-plan.md) | Historical residual reliability implementation session |
| [session-26-plan.md](session-26-plan.md) | Historical residual reliability implementation session |
| [session-27-plan.md](session-27-plan.md) | Historical residual reliability acceptance session |
| [session-28-plan.md](session-28-plan.md) | Historical announcement acceptance session |
| [session-29-plan.md](session-29-plan.md) | Historical lean local measurement session |
| [17-roadmap-closure-audit.md](17-roadmap-closure-audit.md) | Post-execution closure audit and current reading order for the folder |

**Top finding:** The folder has now moved from backlog mode into closure mode. Roadmaps `15` and `16` served as the main execution backlogs through Session `23`, and Sessions `24` through `29` closed the residual group/announcement/measurement track. The closure audit now describes what is historical rationale, what remains open, and what should only be reopened if a real residual gap appears.

---

## 9. Post-Execution State

| Status | Item | Why It Still Matters | Report |
|--------|------|----------------------|--------|
| Maintain | Keep `test-gate-definitions.md` and named gates canonical | Future changes should continue to use the same gate language and command surface | 14 / 15 / 16 |
| Maintain | Keep the lean local messaging measurement events coherent with the current flow-event contract | Future send/retry/media/rejoin work should extend the landed local event layer, not invent a second metrics stack | 10 / 29 |
| Follow up only if needed | Complete external CI / release owner wiring for Session `12` if the local handoff artifact is still the final state | This is the only clearly externalized closure item | 16 |
| Residual only | Reopen group reliability only if voice publish-failure retry becomes a real escaped bug or a clearly justified trust gap | The broader discussion reliability program is closed | 18 / 24 / 25 / 26 / 27 |
| Residual only | Reopen a roadmap item only if a real regression, failed gate, or newly proven gap appears | Avoids restarting broad cleanup work without evidence | 17 |
| Intentionally deferred | Product-scope items such as read receipts, typing indicators, search, exporter/dashboard work | These were deferred by design, not missed correctness work | 08 / 09 / 10 |
| Do not reopen by default | Broad SQL/index/caching work, mass dead-code cleanup, or exporter architecture | These remain unjustified without new evidence | 05 / 06 / 10 |

---

## 10. Closure References

| Report | Focus |
|--------|-------|
| [19-1to1-message-reliability-closure-reference.md](19-1to1-message-reliability-closure-reference.md) | Stable closure bar for trustworthy 1:1 text/media/voice messaging |
| [20-group-discussion-reliability-closure-reference.md](20-group-discussion-reliability-closure-reference.md) | Stable closure bar for trustworthy group discussions under current receipt-less group architecture |
| [21-announcement-reliability-closure-reference.md](21-announcement-reliability-closure-reference.md) | Stable closure bar for trustworthy announcements on top of shared group reliability and admin-only enforcement |

**Top finding:** These three docs are the canonical "stop here unless a real regression appears" references for messaging reliability after the roadmap work. They are intentionally narrower than full feature backlogs and should be used to avoid reopening product-scope or protocol-scope debates by accident.
