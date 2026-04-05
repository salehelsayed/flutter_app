# Test-Flight-1 Improvement Reports

Generated: 2026-04-04

**Closure note:** Sessions `1` through `29` are closed execution artifacts.
`session-30-plan.md` is a plan-only narrow reopen artifact and should not be
read as landed work. `session-31-plan.md`, `session-32-plan.md`,
`session-34-plan.md`, `session-35-plan.md`, `session-36-plan.md`, and
`session-37-plan.md` are completed narrow closure sessions, including the
intro-to-Orbit / intro-to-Feed follow-up closure from Session `35`. Sessions
`44` through `47` are completed Report `24` execution/closure artifacts, with
`24-cancel-media-upload-session-breakdown.md` and the stable messaging closure
references carrying the maintenance-time meaning. Sessions `54` and `55` are
completed Report `27` execution/closure artifacts, with
`27-persistent-nav-bar-orbit-session-breakdown.md` carrying the
maintenance-time meaning. Session `56` is the completed Report `28`
execution/closure artifact, with
`28-orbit-intro-badge-session-breakdown.md` carrying the maintenance-time
meaning. Sessions `58` and `59` are the completed Report `29`
execution/closure artifacts, with
`29-batch-parallel-intro-sending-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Sessions `59` and `60` for Report
`30` are the completed Report `30` execution/closure artifacts, with
`30-swipe-nav-feed-orbit-session-breakdown.md` carrying the maintenance-time
meaning. The doc-scoped Session `1` for Report `34` is the completed Report
`34` execution/closure artifact, with
`34-orbit-intros-swipe-delete-missing-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Session `1` for Report `35` is the
completed narrow reopen/closure artifact for the late-boundary 1:1 video
cancel seam, with
`35-cancelled-video-upload-still-sends-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Sessions `1` through `3` for Report
`41` are the completed inbox-recovery and notification-open trust closure
artifacts, with
`41-notification-open-missing-incoming-messages-session-breakdown.md` plus the
refreshed 1:1 closure reference carrying the maintenance-time meaning. The
doc-scoped Session `1` for Report `44` is the completed Feed/Orbit handled
notification sync closure artifact, with
`44-feed-orbit-notification-desync-session-breakdown.md` carrying the
maintenance-time meaning. The doc-scoped Session `1` for Report `45` is the
completed Feed inline-reply viewport reorientation closure artifact, with
`45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
carrying the maintenance-time meaning. The doc-scoped Session `1` for Report
`48` is the
completed automatic 1:1 inbox-drain fallback removal closure artifact, with
`48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md` plus the
refreshed 1:1 closure reference carrying the maintenance-time meaning. The
doc-scoped Sessions `1` through `10` for Report `50` are the completed
two-simulator coverage-refresh artifacts, with
`50-two-simulator-user-journey-tests-todo-session-breakdown.md` plus the
refreshed audit/journey docs carrying the maintenance-time meaning. The
doc-scoped Sessions `1` and `2` for Report `55` are the completed Report `55`
execution/closure artifacts, with
`55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
carrying the maintenance-time meaning.
Roadmaps `15` and `16` plus the residual reliability/measurement sessions `24`
through `29` remain historical execution artifacts. Reports `01` through `14`
remain the rationale archive. The current closure state lives in Sections `8`,
`9`, and `10` below.

---

## 1. Test Coverage

| Report | Focus |
|--------|-------|
| [01-unit-test-coverage.md](01-unit-test-coverage.md) | Corrected module-by-module unit test picture — broad coverage, narrower remaining gaps |
| [02-integration-test-coverage.md](02-integration-test-coverage.md) | Cross-feature flows, integration quality, and remaining boundary gaps |
| [50-two-simulator-user-journey-tests-coverage-audit.md](50-two-simulator-user-journey-tests-coverage-audit.md) | Refreshed manual-journey coverage matrix plus accepted notification-open contract for the current app |
| [_current-test-map.md](_current-test-map.md) | Compact operator runbook for which tests exist, what they protect, and how to run them now |

**Top finding:** Test coverage is materially stronger than the first pass
suggested. Report `50` is now the folder-local matrix for manual
two/three-simulator journey confidence, `67` is the compact current runbook
for day-to-day test selection, and the old stale Feed-expanded-card
notification-open assumption is retired in favor of the current
conversation/group/intros routing contract.

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
| [12-1to1-chat-use-case-audit.md](12-1to1-chat-use-case-audit.md) | Core 1:1 flows are tested; remaining gaps are product features and narrow residual edges |
| [11-group-discussion-use-case-audit.md](11-group-discussion-use-case-audit.md) | Core group lifecycle/message/recovery flows are tested; stale gap claims removed |
| [13-announcement-use-case-audit.md](13-announcement-use-case-audit.md) | Announcement enforcement is well covered in Flutter; Go-side writer enforcement remains outside this tree |
| [18-group-discussion-reliability-audit.md](18-group-discussion-reliability-audit.md) | Lean reliability-gap review: what group chat still needs to feel as trustworthy as 1:1 without overengineering |

**Top findings:**
- **1:1 Chat:** Core implemented flows are tested; the earlier feed-inline
  durable-send gap, the sender-visible `reuse` fast-path mismatch, and the
  broader direct-vs-relay transport-truth seam for new Go-backed 1:1 rows are
  now closed. The remaining gaps are mostly product features plus narrower
  residual edge cases such as local-file-missing retry behavior
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
| [session-30-plan.md](session-30-plan.md) | Plan-only narrow residual reopen artifact; not executed closure work |
| [session-31-plan.md](session-31-plan.md) | Historical narrow 1:1 transport-label closure session |
| [session-32-plan.md](session-32-plan.md) | Historical narrow 1:1 transport-truth closure session |
| [session-34-plan.md](session-34-plan.md) | Historical narrow standalone CLI-backed transport residual closure session |
| [session-35-plan.md](session-35-plan.md) | Historical narrow intro-to-Orbit / intro-to-Feed follow-up closure session |
| [session-36-plan.md](session-36-plan.md) | Historical narrow standalone CLI-backed post-verify closure session |
| [session-37-plan.md](session-37-plan.md) | Historical narrow 1:1 failed-send recovery regression-coverage closure session |
| [24-cancel-media-upload-session-breakdown.md](24-cancel-media-upload-session-breakdown.md) | Historical multi-session breakdown and closure-owner artifact for Report `24` |
| [session-44-plan.md](session-44-plan.md) | Historical cancelable-upload retry/delete contract session |
| [session-45-plan.md](session-45-plan.md) | Historical 1:1 cancelable-upload surface session |
| [session-46-plan.md](session-46-plan.md) | Historical group/announcement parity session for cancelable uploads |
| [session-47-plan.md](session-47-plan.md) | Historical acceptance-only closure refresh for cancelable uploads |
| [27-persistent-nav-bar-orbit-session-breakdown.md](27-persistent-nav-bar-orbit-session-breakdown.md) | Historical multi-session breakdown and closure-owner artifact for Report `27` |
| [27-persistent-nav-bar-orbit-session-54-plan.md](27-persistent-nav-bar-orbit-session-54-plan.md) | Historical already-covered in-app Orbit persistent-nav session artifact |
| [27-persistent-nav-bar-orbit-session-55-plan.md](27-persistent-nav-bar-orbit-session-55-plan.md) | Historical intro-notification Orbit parity and closure session |
| [28-orbit-intro-badge-session-breakdown.md](28-orbit-intro-badge-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `28` |
| [28-orbit-intro-badge-session-56-plan.md](28-orbit-intro-badge-session-56-plan.md) | Historical shared Orbit intro badge and freshness-wiring session artifact |
| [29-batch-parallel-intro-sending-session-breakdown.md](29-batch-parallel-intro-sending-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `29` |
| [29-batch-parallel-intro-sending-session-58-plan.md](29-batch-parallel-intro-sending-session-58-plan.md) | Historical capped intro batching and progress-contract session artifact |
| [29-batch-parallel-intro-sending-session-59-plan.md](29-batch-parallel-intro-sending-session-59-plan.md) | Historical picker progress UX and closure session artifact |
| [30-swipe-nav-feed-orbit-session-breakdown.md](30-swipe-nav-feed-orbit-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `30` |
| [30-swipe-nav-feed-orbit-session-59-plan.md](30-swipe-nav-feed-orbit-session-59-plan.md) | Historical shared-host migration and preserved-state session artifact for Report `30` |
| [30-swipe-nav-feed-orbit-session-60-plan.md](30-swipe-nav-feed-orbit-session-60-plan.md) | Historical horizontal swipe / gesture arbitration closure session artifact for Report `30` |
| [34-orbit-intros-swipe-delete-missing-session-breakdown.md](34-orbit-intros-swipe-delete-missing-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `34` |
| [34-orbit-intros-swipe-delete-missing-session-1-plan.md](34-orbit-intros-swipe-delete-missing-session-1-plan.md) | Historical live Orbit intro swipe-delete / closure session artifact for Report `34` |
| [35-cancelled-video-upload-still-sends-session-breakdown.md](35-cancelled-video-upload-still-sends-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `35` |
| [35-cancelled-video-upload-still-sends-session-1-plan.md](35-cancelled-video-upload-still-sends-session-1-plan.md) | Historical late-boundary 1:1 video cancel reopen/closure session artifact for Report `35` |
| [41-notification-open-missing-incoming-messages-session-breakdown.md](41-notification-open-missing-incoming-messages-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-1-plan.md](41-notification-open-missing-incoming-messages-session-1-plan.md) | Historical two-phase relay inbox retrieve/ack session artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-2-plan.md](41-notification-open-missing-incoming-messages-session-2-plan.md) | Historical durable inbox staging/replay and reject-observability session artifact for Report `41` |
| [41-notification-open-missing-incoming-messages-session-3-plan.md](41-notification-open-missing-incoming-messages-session-3-plan.md) | Historical app-root notification parity and closure session artifact for Report `41` |
| [44-feed-orbit-notification-desync-session-breakdown.md](44-feed-orbit-notification-desync-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `44` |
| [44-feed-orbit-notification-desync-session-1-plan.md](44-feed-orbit-notification-desync-session-1-plan.md) | Historical Feed/Orbit handled-notification sync and closure session artifact for Report `44` |
| [45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md](45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `45` |
| [45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md](45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md) | Historical Feed inline-reply viewport reorientation and closure session artifact for Report `45` |
| [48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md](48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md) | Historical doc-scoped breakdown and closure-owner artifact for Report `48` |
| [48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md](48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md) | Historical automatic 1:1 inbox-drain fallback removal and closure session artifact for Report `48` |
| [50-two-simulator-user-journey-tests-todo-session-breakdown.md](50-two-simulator-user-journey-tests-todo-session-breakdown.md) | Closed doc-scoped controller for Report `50` manual-journey coverage refresh |
| [50-two-simulator-user-journey-tests-todo-session-10-plan.md](50-two-simulator-user-journey-tests-todo-session-10-plan.md) | Historical closure-only matrix refresh and accepted-difference session artifact for Report `50` |
| [55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md](55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md) | Closed doc-scoped controller for Report `55` iOS share handoff plus multi-recipient picker/batch-send rollout |
| [55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md](55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md) | Historical iOS auto-redirect handoff proof session artifact for Report `55` |
| [55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md](55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md) | Historical picker multi-select batch-send and closure session artifact for Report `55` |
| [17-roadmap-closure-audit.md](17-roadmap-closure-audit.md) | Post-execution closure audit and current reading order for the folder |

**Top finding:** The folder has now moved from backlog mode into closure mode.
Roadmaps `15` and `16` served as the main execution backlogs through Session
`23`, Sessions `24` through `29` closed the residual
group/announcement/measurement track, Sessions `31` and `32` closed the narrow
1:1 transport-label and transport-truth seams, Session `35` closed the narrow
intro-to-Orbit / intro-to-Feed stale follow-up seam, Sessions `34` and `36`
closed the reviewed standalone CLI-backed transport and post-verify proof
seams, Session `37` closed the narrow deterministic failed-send recovery
coverage seam, Sessions `44` through `47` closed the Report `24`
cancelable-upload rollout and refreshed the stable messaging closure refs,
Sessions `54` and `55` closed the Report `27` persistent-nav rollout and
refreshed the folder closure docs, Session `56` closed the Report `28` shared
Orbit intro badge truth and freshness wiring seam and refreshed the closure
docs, Sessions `58` and `59` closed the Report `29` ordered intro-batching and
truthful picker-progress rollout, the doc-scoped Sessions `59` and `60`
closed the Report `30` shared-host plus horizontal-swipe Feed/Orbit rollout,
the doc-scoped Session `1` for Report `35` reclosed the narrow late-boundary
1:1 video cancel seam without reopening the broader Report `24`
cancelable-upload program, the doc-scoped Sessions `1` through `3` for Report
`41` closed the staged inbox recovery plus app-root notification-open trust
seam and refreshed the stable 1:1 closure wording, the doc-scoped Session `1`
for Report `44` closed the stale Feed/Orbit handled-notification contradiction
without widening into app-root notification routing or unread architecture
work, the doc-scoped Session `1` for Report `45` closed the stale absolute
scroll-offset seam after successful inline reply without widening into
unread-model redesign or broader Feed/Orbit navigation architecture, the
doc-scoped Session `1` for Report `48` closed the automatic inbox-drain path
from durable `retrieve_pending` back to destructive `inbox:retrieve`,
refreshed the stable 1:1 closure wording without widening into public
inbox-API removal, the doc-scoped Sessions `1` through `10` for Report `50`
closed the manual-journey coverage backlog plus the stale notification-open
assumption, the doc-scoped Sessions `1` and `2` for Report `55` closed the
external-share iOS handoff plus truthful multi-recipient picker/batch-send
rollout without widening into Android entry or composer redesign, and Session
`30` remains a plan-only residual artifact rather than executed work.
The closure audit now describes what is historical rationale, what remains
open, and what should only be reopened if a real residual gap appears.

---

## 9. Post-Execution State

| Status | Item | Why It Still Matters | Report |
|--------|------|----------------------|--------|
| Maintain | Keep `test-gate-definitions.md` and named gates canonical | Future changes should continue to use the same gate language and command surface | 14 / 15 / 16 |
| Maintain | Keep the lean local messaging measurement events coherent with the current flow-event contract | Future send/retry/media/rejoin work should extend the landed local event layer, not invent a second metrics stack | 10 / 29 |
| Maintain | Use the direct standalone CLI-backed transport command alongside the named transport gate when touching the Sessions `34` / `36` seams | The named transport gate can run `transport_e2e_test.dart` without the CLI fixture/orchestrator path | 19 / 34 / 36 |
| Maintain | Use the direct intro/orbit/feed maintenance suite plus `baseline` when intro follow-up wiring changes | No named gate directly owns this seam; maintenance-time safety sits in `orbit_wired_test.dart`, `orbit_intros_wiring_test.dart`, `feed_wired_test.dart`, and the intro listener/regression/integration suites | 35 / test-gate-definitions |
| Maintain | Use `50-two-simulator-user-journey-tests-todo-session-breakdown.md` plus the refreshed Report `50` audit/journey docs when manual two/three-simulator coverage claims are questioned | Report `50` is now the closure-time controller for this matrix, including the accepted notification-open routing difference and the exact direct suites that closed Sessions `1` through `9` | 50 |
| Maintain | Use the stable 1:1/group closure refs plus `24-cancel-media-upload-session-breakdown.md` and `35-cancelled-video-upload-still-sends-session-breakdown.md` for cancelable-upload maintenance | Session `47` closed the broad rollout and the doc-scoped Session `1` for Report `35` reclosed the narrow late-boundary 1:1 video cancel seam without widening gate definitions or announcement-specific architecture | 19 / 20 / 24 / 35 / 47 |
| Maintain | Use `41-notification-open-missing-incoming-messages-session-breakdown.md`, the direct notification-open suites, `./scripts/run_test_gates.sh 1to1`, and `baseline` when shared 1:1 inbox recovery or app-root notification-open routing changes | The doc-scoped Report `41` sessions closed durable fetched-envelope staging/replay plus prepare-before-route parity for terminated remote, warm remote, terminated local, and warm local notification opens; `transport` becomes required again only if later work broadens into startup/resume/inbox-drain ordering changes | 19 / 41 / test-gate-definitions |
| Maintain | Use `48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`, the direct automatic-drain service/lifecycle suites, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh baseline`, and `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` when shared automatic 1:1 inbox drain or `retrieve_pending` fallback wiring changes | The doc-scoped Session `1` for Report `48` closed the production path from durable automatic drain back to destructive `inbox:retrieve` without widening into public destructive-API removal or malformed-row cleanup architecture | 19 / 41 / 48 / test-gate-definitions |
| Maintain | Use `27-persistent-nav-bar-orbit-session-breakdown.md`, `intro_notification_orbit_route_test.dart`, the direct Orbit/Feed nav suites, and `baseline` when app-root intro-open wiring changes | Session `55` closed the notification-opened Orbit persistent-nav seam without widening into sibling-tab hosting, keep-alive, or swipe navigation scope | 27 / 54 / 55 |
| Maintain | Use `28-orbit-intro-badge-session-breakdown.md`, the direct Feed/Orbit intro badge suites, `intro_notification_orbit_route_test.dart`, and `baseline` when shared Orbit pending-intro badge truth changes | Session `56` closed shared badge coexistence, expiry-aware load, live refresh, route-return freshness, and persistent-nav Orbit parity without widening into a second unread system or root-owned badge controller | 28 / 56 |
| Maintain | Use `29-batch-parallel-intro-sending-session-breakdown.md`, the direct intro application/picker/integration suites, and rerun `baseline` only when broader conversation or banner entry wiring changes | Sessions `58` and `59` closed capped batch intro sending plus truthful picker progress without widening into Go/bridge batch APIs or new named-gate ownership | 29 / 58 / 59 |
| Maintain | Use `55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`, the direct share picker/coordinator/integration suites, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` when shared external-share picker or share fanout wiring changes | The doc-scoped Sessions `1` and `2` for Report `55` closed the iOS share-entry handoff plus truthful multi-recipient picker/batch-send slice without widening into Android entry, composer redesign, or shared 1:1/group send semantics | 55 / test-gate-definitions |
| Maintain | Use `30-swipe-nav-feed-orbit-session-breakdown.md`, the direct Feed/Orbit swipe and local-gesture suites, and `baseline` when the shared Feed/Orbit navigation seam changes | The doc-scoped Sessions `59` and `60` closed the shared-host plus horizontal-swipe rollout without widening into notification-opened Orbit routing parity, a broader app-root tab shell, or unread/badge architecture work | 30 / 59 / 60 |
| Maintain | Use `44-feed-orbit-notification-desync-session-breakdown.md`, the direct `feed_wired_test.dart` and `orbit_wired_test.dart` suites, plus `./scripts/run_test_gates.sh feed`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` when shared Feed/Orbit handled-notification truth changes | The doc-scoped Session `1` for Report `44` closed the mounted Orbit stale-unread contradiction after Feed collapse or successful inline reply without widening into app-root notification routing, group sync, or unread-architecture redesign | 30 / 40 / 44 / test-gate-definitions |
| Maintain | Use `45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`, the direct `feed_wired_test.dart` and `feed_screen_test.dart` suites, plus `./scripts/run_test_gates.sh feed`, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` when Feed inline-reply viewport continuity changes | The doc-scoped Session `1` for Report `45` closed the stale same-card viewport continuity seam after successful inline reply without widening into unread-truth redesign, group parity, or broader Feed/Orbit navigation architecture | 40 / 44 / 45 / test-gate-definitions |
| Maintain | Use `34-orbit-intros-swipe-delete-missing-session-breakdown.md`, `orbit_wired_test.dart`, `orbit_intros_wiring_test.dart`, `orbit_screen_archived_groups_test.dart`, `swipeable_friend_row_test.dart`, and `baseline` when live Orbit intro delete behavior changes | The doc-scoped Session `1` closed the live Orbit intro swipe-delete seam without widening into intro protocol, loader, or broader Feed/Orbit architecture work | 34 / doc-scoped 1 |
| Follow up only if needed | Complete external CI / release owner wiring for Session `12` if the local handoff artifact is still the final state | This is the only clearly externalized closure item | 16 |
| Follow up only if needed | Revalidate Session `30` before any execution | The plan file alone should not reopen the already-closed broader program | 17 / 30 |
| Residual only | Reopen group reliability only if voice publish-failure retry becomes a real escaped bug or a clearly justified trust gap | The broader discussion reliability program is closed | 18 / 24 / 25 / 26 / 27 |
| Residual only | Reopen intro follow-up work only if a real regression makes `mutualAccepted` contacts reappear under `Intros`, hides the Feed connection card, or breaks the blocked-accept listener contract | Session `35` closed the UI-state race without reopening listener or protocol work | 35 |
| Residual only | Reopen Orbit intro badge work only if pending-intro badge truth regresses on cold load, live intro updates, route return from Orbit accept/pass, or persistent-nav Orbit parity | Session `56` closed the report; later work should reopen only on real badge-truth regressions, not to invent a new root-level badge architecture | 28 / 56 |
| Residual only | Reopen live Orbit intro delete work only if swipe-delete affordance, confirmation, grouped-row cleanup, empty-state truth, or pending-intro badge truth regresses after delete | The doc-scoped Session `1` for Report `34` closed the local Orbit intro delete seam; later work should reopen only on real UI/count regressions, not to invent P2P delete sync or widened intro-status scope | 34 / doc-scoped 1 |
| Residual only | Reopen 1:1 transport-label/truth work only if new outgoing or incoming 1:1 rows regress to misleading transport labels | Sessions `31` and `32` closed new-row reuse fast-path labeling and Go/libp2p direct-vs-relay truth; old `reuse` rows remain legacy-only fallback | 19 / 31 / 32 |
| Residual only | Reopen 1:1 failed-send recovery coverage only if the deterministic foreground online-transition or lock-after-failure resume regressions stop proving exact-once healing | Session `37` closed the missing matrix cell for visible failure during network switch followed by later foreground or resume recovery | 19 / 33 / 37 |
| Residual only | Reopen the late-boundary 1:1 video cancel seam only if accepted cancel again falls through into the ordinary upload-failure UX or the later final-send path for that same attempt | The doc-scoped Session `1` for Report `35` reclosed that narrow seam without reopening group parity, retry ownership, or status-model scope | 19 / 24 / 35 |
| Residual only | Reopen standalone CLI-backed transport work only if a current direct run reintroduces the previously closed transport-truth or post-verify proof seams | Sessions `34` and `36` closed the reviewed `A1` / `A4` / `A2` / `A5` / `D4` / `A7` / `A8` / `A8b` / `C3` / `B8` / `G6` / `E8` / `RECV-A1` / `RECV-A4` / `RECV-A6` seams; the direct command remains required maintenance proof alongside the named gate | 19 / 34 / 36 |
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

---

## 11. Feature Specs (New Work)

| Report | Focus |
|--------|-------|
| [22-media-transfer-size-limit.md](22-media-transfer-size-limit.md) | Raise media transfer cap from 100 MB to 5 GB with attach-time warning, compression enforcement, wake lock, and progress UX |
| [24-cancel-media-upload.md](24-cancel-media-upload.md) | Cancel in-progress uploads, delete/retry failed messages, prevent unwanted auto-retries |
| [25-delete-intro-swipe.md](25-delete-intro-swipe.md) | Swipe-to-delete introductions in Orbit Intros tab with DB removal and re-introduction support |
| [26-long-press-message-context-menu.md](26-long-press-message-context-menu.md) | Signal-like long-press overlay with emoji bar, blurred background, and Reply/Copy context menu on messages |
| [27-persistent-nav-bar-orbit.md](27-persistent-nav-bar-orbit.md) | Bottom nav bar disappears when navigating to Orbit; should persist with active tab indicator |
| [28-orbit-intro-badge.md](28-orbit-intro-badge.md) | Badge/dot on Orbit nav button when pending introductions exist |
| [29-batch-parallel-intro-sending.md](29-batch-parallel-intro-sending.md) | Ordered batched introduction sending with concurrency cap of 10 and truthful picker progress |
| [30-swipe-nav-feed-orbit.md](30-swipe-nav-feed-orbit.md) | Horizontal swipe navigation between Feed and Orbit screens |
| [31-edit-last-sent-message.md](31-edit-last-sent-message.md) | Edit last sent message via long-press context menu with P2P sync |
| [32-notification-card-interactions.md](32-notification-card-interactions.md) | Profile picture tap and collapse bar non-responsive on notification-opened feed cards |
| [33-delete-message-for-me-everyone.md](33-delete-message-for-me-everyone.md) | Delete messages with "Delete for Me" and "Delete for Everyone" via long-press context menu |
| [34-orbit-intros-swipe-delete-missing.md](34-orbit-intros-swipe-delete-missing.md) | Live Orbit intros are missing the existing swipe-to-delete affordance and confirmation flow |
| [35-cancelled-video-upload-still-sends.md](35-cancelled-video-upload-still-sends.md) | Accepted cancel on a 1:1 video upload can still fall through into failure/send; cancel should stop delivery for that attempt |
| [55-external-share-skip-post-and-multi-recipient-plan.md](55-external-share-skip-post-and-multi-recipient-plan.md) | Skip the extra native iOS Post screen on external share and support truthful multi-recipient share delivery from the picker |

**Context:** These specs address user-facing gaps discovered during TestFlight
usage. Report `24` directly relates to the upload reliability path covered by
reports `08`, `19`, and `22`, and its landed maintenance-time meaning now
lives in `24-cancel-media-upload-session-breakdown.md` plus the refreshed
closure references rather than in the proposal alone. Report `27` directly
relates to the intro/orbit/feed navigation seam first narrowed by Session
`35`, and its landed maintenance-time meaning now lives in
`27-persistent-nav-bar-orbit-session-breakdown.md` plus the refreshed closure
docs rather than in the proposal alone. Report `28` directly relates to that
same intro/orbit/feed seam, and its landed maintenance-time meaning now lives
in `28-orbit-intro-badge-session-breakdown.md` plus the refreshed closure docs
rather than in the proposal alone. Report `29` directly relates to the same
intro sending seam, and its landed maintenance-time meaning now lives in
`29-batch-parallel-intro-sending-session-breakdown.md` plus the refreshed
closure docs rather than in the proposal alone. Report `30` directly relates to
that same Feed/Orbit navigation seam, and its landed maintenance-time meaning
now lives in `30-swipe-nav-feed-orbit-session-breakdown.md` plus the refreshed
closure docs rather than in the proposal alone. Report `34` directly relates to
the same intro/orbit/feed seam, and its landed maintenance-time meaning now
lives in `34-orbit-intros-swipe-delete-missing-session-breakdown.md` plus the
refreshed closure docs rather than in the proposal alone. Report `35` directly
relates to the Report `24` 1:1 cancel seam, and its landed maintenance-time
meaning now lives in
`35-cancelled-video-upload-still-sends-session-breakdown.md` plus the
refreshed 1:1 closure docs rather than in the proposal alone. Report `55`
directly relates to the external-share entry and delivery seam, and its landed
maintenance-time meaning now lives in
`55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
rather than in the proposal alone.
