# Unit Test Coverage Analysis

**Total Source Files:** 528 | **Total Test Files:** 542 | **Overall Ratio:** 102%

---

## Executive Summary

Good overall test density. The earlier pass overstated several “critical gaps,” especially in Posts, Introduction, Groups, and StartupRouter. The current repo already has substantial coverage across those areas. The remaining high-value gaps are narrower: notification-service adapter boundaries, nearby-post presence validation branches, and a few feature-specific correctness checks such as announcement-specific group creation.

---

## Coverage by Module

### Tier 1: Strongly Covered

| Module | Source | Tests | Rating | Notes |
|--------|--------|-------|--------|-------|
| posts | 85 | 91 | Strong | Phase 1-5 use cases already covered (`send_post`, comment/reaction, pass-along, pins, repost delivery) |
| conversation | 49 | 70 | Strong | Core send/receive/retry/reaction/conversation UI flows broadly covered |
| contact_request | 13 | 15 | Strong | Use cases, dialogs, listener flow covered |
| introduction | 23 | 27 | Strong | Core use cases already covered (`send`, `accept`, `mutual_acceptance`, banner logic, regressions) |
| settings | 14 | 14 | Strong | Wired/settings flows, profile picture integration, QR/recovery-related surfaces covered |
| push | 10 | 11 | Strong | Good unit coverage plus open-flow/deep-link integration around notifications |
| bridge (core) | 4 | 6 | Strong | Bridge client and request formatting well covered |
| share | 5 | 5 | Strong | Core share flows already exercised |

### Tier 2: Broad But Uneven

| Module | Source | Tests | Rating | Gap Count | Key Gaps |
|--------|--------|-------|--------|-----------|----------|
| groups | 60 | 64 | Broad | Moderate | Coverage is good overall; remaining gaps are more product-feature scope than core correctness |
| identity | 19 | 17 | Broad | Low | `startup_router.dart` is already covered; remaining gaps are narrower UI/plugin boundaries |
| feed | 41 | 37 | Broad | Moderate | Feed projection/store logic covered; remaining gaps are mostly cross-surface behavior and durability parity |
| qr_code | 9 | 7 | Broad | Low | Core scan/parse logic and wired UI are covered; deeper integration is selective |
| orbit | 24 | 22 | Broad | Moderate | Main screens/widgets covered; some models/widgets still lighter |
| home | 11 | 8 | Moderate | Moderate | Some avatar/ring presentation coverage still uneven |

### Tier 3: Moderate / Targeted Gaps

| Module | Source | Tests | Rating | Gap Count | Key Gaps |
|--------|--------|-------|--------|-----------|----------|
| database (core) | 71 | 46 | Moderate | High by file count, lower by risk | Many migration files remain lightly covered individually, but the full chain is already tested |
| notifications (core) | 6 | 4 | Moderate | Narrow | Adapter boundaries like `flutter_notification_service.dart` and `local_notification_support.dart` |
| media (core) | 9 | 8 | Moderate | Narrow | Some platform/plugin boundaries remain light |
| local_discovery (core) | 6 | 5 | Moderate | Narrow | Base services covered; platform/network edge behavior remains selective |
| utils (core) | 10 | 6 | Moderate | Narrow | Diagnostics/timing helpers are lighter, but also lower risk |

### Tier 4: Weak / Boundary-Oriented

| Module | Source | Tests | Rating | Key Gaps |
|--------|--------|-------|--------|----------|
| secure_storage (core) | 3 | 1 | Weak | Real plugin boundary coverage is light; add only if regressions appear |
| theme (core) | 4 | 1 | Weak | Mostly visual/static concerns, low correctness risk |
| config (core) | 1 | 0 | Weak | `startup_config.dart` exists, but this is not currently a top-value test target |
| constants (core) | 2 | 1 | Weak | Low business-risk area |

---

## Layer-wise Breakdown

| Layer | Estimated Coverage | Status |
|-------|-------------------|--------|
| Application (use cases) | 90-95% | STRONG |
| Domain (models, repos) | 85-90% | GOOD |
| Presentation (UI widgets/screens) | 60-70% | MODERATE |
| Infrastructure/Services | 70-80% | MODERATE |
| Database/Migrations | 60-70% | MODERATE |

---

## Critical Test Gaps (Action Items)

### Priority 1: HIGH-CONFIDENCE (1-2 days)

**1. Notification Adapter Boundary (3-4 tests, 0.5-1 day)**
- [ ] `flutter_notification_service_test.dart`
- [ ] `local_notification_support_test.dart`
- [ ] Verify initial payload consumption, tap callback forwarding, and channel/category setup

**2. Nearby Post Presence Validation (4-6 tests, 0.5-1 day)**
- [ ] `handle_incoming_post_presence_use_case_test.dart`
- [ ] Cover blocked sender, stale snapshot, sender/payload mismatch, malformed timestamps

**3. Announcement-Specific Group Creation (1-2 tests, 1-2 hours)**
- [ ] Extend `create_group_use_case_test.dart` with `GroupType.announcement`
- [ ] Verify type persistence and UI-facing config remain correct

### Priority 2: USEFUL BUT NOT URGENT (1-2 days)

**4. Onboarding Golden Path (1 test, ~1 day)**
- [ ] One end-to-end happy path: identity creation → contact request → first message
- [ ] Valuable as a single confidence test, but not a critical missing foundation

**5. Regression Coverage After Product Fixes**
- [ ] Add targeted tests only when fixing durable send-path parity or identity caching
- [ ] Prefer narrow regression tests over broad “retest the module” sweeps

### Priority 3: DEFER / NOT CURRENT PRIORITIES

- Broad re-sweeps of Posts use cases
- Broad re-sweeps of Introduction use cases
- Re-testing `startup_router.dart` as if it were uncovered
- Extra feed snapshot rewrites
- Migration smoke rewrites without a migration-specific bug
- `startup_config_test.dart` as a standalone priority

---

## Evidence Already Present

- Posts core use cases already have direct tests such as `send_post_use_case_test.dart`, `send_post_comment_use_case_test.dart`, `send_post_reaction_use_case_test.dart`, `pass_post_along_use_case_test.dart`, and `pin_post_use_case_test.dart`.
- Introduction core use cases already have direct tests such as `send_introduction_test.dart`, `accept_introduction_test.dart`, `mutual_acceptance_test.dart`, and `create_connection_on_mutual_acceptance_test.dart`.
- Startup routing already has meaningful coverage via `startup_router_test.dart` and `startup_router_recovery_test.dart`.
- Feed projection/store behavior already has direct coverage via `feed_projection_test.dart` and `feed_store_test.dart`.
- Migration confidence is stronger than raw file counts suggest because the repo already includes full-chain migration coverage.
