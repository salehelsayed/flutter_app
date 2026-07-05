# 214 - Orbit as the Main Screen: Post-Onboarding + Cold-Start Landing (Modification)

Status: awaiting-review
Spec: free-text intent (no formal spec) — "when user-a scans the QR of user-b or accepts the first friend request, user-a immediately moves to Feed. Change that: move directly to Orbit. Orbit will be the main screen, not the feed."

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-05 | Evidence Collector (workflow `wf_b93c257f-4ef`: 1 scout + 1 seam + 1 test-inventory + 8 verify + 8 refute agents) | startup_router.dart, startup_decision.dart, first_time_experience_wired.dart, qr_scanner_wired.dart, app_shell_controller.dart, app_shell_tab.dart, feed_wired.dart, orbit_wired.dart, main.dart, post_notification_open_coordinator.dart, feed_route_transition.dart + 30 test files | 8/8 claims CONFIRMED, 0 refuted. Landing surface is decided by `AppShellController.activeTab` (in-memory, defaults `feed`, never persisted); all three landings push the same `FeedWired` shell | design the seam |
| 2026-07-05 | Planner | tier-matrix, sufficiency-checklist, run_test_gates.sh gate names, `grep AppShellController(` (lib: 1 bare prod site; test: 28 files) | Single-seam fix: flip the class default (+ invalid-coercion fallback) to `AppShellTab.orbit`. Rejected main.dart-injection variant: it makes the flipped widget tests vacuous (fixture-config, not production behavior) | emit matrix + plan |
| 2026-07-05 | Reviewer (sufficiency) | this plan vs references/sufficiency-checklist.md | All gates pass; matrix has zero empty cells; blind-spot sweep: 2 rows + 2 justified N/A | hand to Arbiter |
| 2026-07-05 | Arbiter | — | No structural blockers. Largest execution risk is fixture triage breadth (≈28 test files construct the controller bare); policy defined in Step 4 | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-05 | contract extraction (git status --short) | — | snapshot recorded: 211 uncommitted set + live sibling claude sessions on tree | scope confirmed; surgical staging required | RED |
| 2026-07-05 | RED tests added | app_shell_controller_test (flip+coercion), qr 5q flip, fte 5o flip + deps extend, NEW startup_router_home_surface_test, NEW onboarding_landing_surface_test, intro-notif orbit-resting sentinel, feed_wired 2× orbit-initial | focused `flutter test` runs: TC-01 2 failing (default=feed), TC-02/03 failing on activeTab, TC-04 landing failing + flow-event sentinel passing, TC-05 failing on activeTab (shell+root assertions passed) | all RED for documented reasons; **TC-07 both GREEN on HEAD** (orbit-initial pause+swipe wiring already correct — recorded, no prod fix needed); TC-06 sentinel green | implement |
| 2026-07-05 | implementation | lib/features/feed/application/app_shell_controller.dart ONLY (default `:22` + coercion `:27` → orbit, doc comment) | — | single seam as planned | direct GREEN |
| 2026-07-05 | direct GREEN | — | all §1-§7 files re-run: app_shell_controller 5/5, qr 7/7, fte 15/15 (one 214-caused pending-timer flush added to notPending buffered-share test), home_surface+landing 3/3, intro-notif 3/3, feed TC-07 2/2 | RED→GREEN transition doubles as mutation proof | triage |
| 2026-07-05 | fixture triage | pinned `initialTab: feed`: feed_wired_test setUp, feed_swipe, feed_focus, feed_contract_preservation, feed_wired_bg_task, share_to_contact_smoke, feed/application/app_shell_controller_test TC-163-01, intro_notification setUp, orbit_unread TC-194-12, orbit_wired TC-163-10+TC-193-40 (surgical, NOT blanket). Meaning-updates: post_notification_open_flow 6 pending-state assertions → orbit resting (reveal tests keep forced-feed, now a REAL transition); orbit_prototypes_removed_guard TC-205-12 coercion → orbit | settings suites (198), startup recovery/notification/early-discovery, orbit_wired remaining 20 bare sites: verified green BARE — not pinned | gates |
| 2026-07-05 | named gates | scripts/run_test_gates.sh: 3 files appended to BASELINE_TESTS (# 214) | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` PASS (131 host + 2 integration); `feed` PASS 294 (292+TC-07×2); `groups` PASS 1153; `posts` PASS; `completeness-check` PASS 1023/1023; `flutter analyze` 0 new (1636 pre-existing); `git diff --check` clean | feature-host-all: run 1 = 1 transient shard fail (feed_wired_test; passes standalone + in feed gate ×2), run 2 = compile fail from CONCURRENT session's in-flight 207 dock work (orbit_intro_dock l10n) — environment, not 214 | QA/smoke |
| 2026-07-06 | QA / sim smoke | — | two-sim smoke BLOCKED: shared tree does not compile mid-edit by live sibling session (215 chat-on-top + 207 dock); commit tree = HEAD+214-only, verified green pre-breakage | blocking: none for 214 scope; sim smoke deferred to post-215 tree | commit |

## Source Of Truth
- Spec / intent: inline above (user request 2026-07-05)
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
A first-run user creates an identity and lands on the intro QR/scan screen (`FirstTimeExperienceWired`). From there, both exits that establish the first contact hardcode Feed: a successful one-scan mutual add ends with the QR-success dialog's OK doing `pushAndRemoveUntil(buildFeedSlideUpRoute(FeedWired), (route) => false)` (`qr_scanner_wired.dart:382-434`), and accepting the first incoming friend request does `pushReplacement(buildFeedSlideUpRoute(FeedWired))` (`first_time_experience_wired.dart:243-291`). Separately, every normal cold start with ≥1 contact lands on Feed: `StartupRouter`'s `hasIdentityWithContacts` branch pushes `FeedWired` (`startup_router.dart:351-459`) and the shell's tab controller defaults to `feed`.

The product decision is: **Orbit is the main screen.** Both post-onboarding landings and every cold start must show the Orbit surface. Feed stays fully reachable (host swipe / persistent nav), and `FeedWired` remains the root shell widget — it hosts BOTH panes and renders whichever `AppShellTab` is active.

What must improve: the three landings (post-scan, post-accept, cold start with contacts) render the Orbit pane, not the Feed pane.
What must stay unchanged (→ preserved-green sentinels): Feed reachability + feed-pane behavior; Orbit exits still land on Feed; the FTE accept-failure branch (red snackbar, no navigation); post-notification posts opens still force Feed (TestFlight posts-hidden design); `openIntroNotificationOrbitRoute` returnTab restore mechanics; startup warm-recovery scheduling; stack shape (pushAndRemoveUntil root nuke; `FeedWired` as first route — six `popUntil(isFirst)` sites depend on it).

## Root Cause (verify → refute confirmed)
Not a bug — a designed default. The landing surface is decided by ONE value: `AppShellController.activeTab`, an in-memory `ChangeNotifier` field whose constructor default is `AppShellTab.feed` (`app_shell_controller.dart:21-27`, invalid values also coerced to `feed`), constructed bare exactly once in production (`main.dart:2403`), never persisted (startup restores only `backgroundPreference`, `startup_router.dart:307-311`). None of the three landing paths ever calls `switchTo`, so all of them render the default tab:
- Scan: `qr_scanner_wired.dart:382-434` — zero `switchTo` calls in the file (verified).
- Accept: `first_time_experience_wired.dart:217-306` — success/notPending → pushReplacement shell; else snackbar.
- Cold start: `startup_router.dart:351-459` → `_pushStartupReplacement(builder: buildFeed)` (L459, impl L1037-1050); the share-intent detour's `onClose` (L430-434) pushes the **identical** `buildFeed` closure.
- `FeedWired` already honors a non-feed initial tab at mount: `initState` sets `_hasMountedOrbitHost = _activeTab == AppShellTab.orbit` and seeds the host swipe controller 1.0/0.0 (`feed_wired.dart:373-381`).

Therefore the fix is the class default (+ coercion fallback) → `AppShellTab.orbit`. All three landings flip at once; the shell, exits, swipe, notification routes need no production edits (verified per-path below).

Refuted / do-NOT-re-introduce: none refuted (8/8 claims survived the adversarial pass). Two confirmed nuances that must NOT be "fixed":
- `openIntroNotificationOrbitRoute` (`main.dart:3410-3436`) self-adapts under orbit-as-home: the `switchTo(orbit)` is guarded (:3422) AND `switchTo` early-returns on same-tab (`app_shell_controller.dart:36-39`) — doubly protected no-op. Do not touch it.
- `PostNotificationOpenCoordinator._revealPosts` forces `switchTo(feed)` deliberately ("Posts tab hidden for TestFlight", `post_notification_open_coordinator.dart:125-126`). Do not "modernize" it to orbit.

## Real Scope
In scope: `app_shell_controller.dart:22` default `initialTab = AppShellTab.orbit` + `:27` coercion fallback `AppShellTab.orbit` (one production file); flip/extend the tests named in the matrix; pin 3 test files into `BASELINE_TESTS`; mechanical fixture pinning (`initialTab: AppShellTab.feed`) in suites that arrange feed-first behavior.
Out of scope (named owners): persisting the last-active tab (no owner — deliberately NOT wanted: orbit is ALWAYS home); renaming `FeedWired`/`buildFeedSlideUpRoute`/`ID_STARTUP_ROUTE_FEED` (cosmetic churn, future rename session if ever); redefining Orbit exit semantics (Feed is the only sibling pane — exits stay); a registered simulator scenario for the FTE landing (camera-driven QR scan is impractical on sims; manual smoke below); Orbit product content for 1-contact users (Orbit feature backlog).

## Files To Inspect Next
Production (single seam + verified-unchanged neighbors): `lib/features/feed/application/app_shell_controller.dart` (EDIT); read-only context: `lib/main.dart:2403,3410-3436`, `lib/features/identity/presentation/startup_router.dart:351-459`, `lib/features/home/presentation/screens/first_time_experience_wired.dart:217-306`, `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart:382-434`, `lib/features/feed/presentation/screens/feed_wired.dart:373-381,2334-2570`, `lib/features/orbit/presentation/screens/orbit_wired.dart:2354-2380`.
Direct tests: `test/features/posts/phase1/app_shell_controller_test.dart`, `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`, `test/features/home/presentation/screens/first_time_experience_wired_test.dart`, NEW `test/features/identity/presentation/screens/startup_router_home_surface_test.dart`, NEW `test/features/home/integration/onboarding_landing_surface_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/push/application/intro_notification_orbit_route_test.dart`.
Dependency-only context: `test/features/orbit/presentation/screens/orbit_wired_test.dart` (22 bare controller constructions — exit assertions force tabs explicitly, expected unaffected), `test/features/settings/presentation/screens/settings_wired_test.dart` + feed suite fixtures (triage list, Step 4).

## Existing Tests Covering This Area
- `qr_scanner_wired_test.dart::'5q: QR scan success without buffered intent navigates to feed only'` — the post-scan destination lock (exists; asserts `find.byType(FeedWired)`; FLIPS). In `BASELINE_TESTS` (run_test_gates.sh:10).
- `first_time_experience_wired_test.dart::'5o: accept success without buffered intent navigates to feed only'` + `'accept success forwards nearby dependencies into feed'` — post-accept locks (exist; FLIP/extend). AUTO glob only.
- `posts/phase1/app_shell_controller_test.dart::'defaults to feed and accepts orbit as a first-class tab'` — THE default-tab lock (exists; FLIPS). AUTO glob.
- `startup_router_recovery_test.dart` — FeedWired-as-root asserted ONLY on the migration-activation path (L393); `BASELINE_TESTS` (:9). No positive lock for the normal `hasIdentityWithContacts` landing (MISSING → TC-214-04).
- `feed_wired_test.dart` — shell round trips, swipe thresholds, 163 off-screen pause, Settings round-trip; `FEED_TESTS` (:182). No orbit-INITIAL-mount coverage (MISSING → TC-214-07).
- `orbit_wired_test.dart` — embedded/persistent exits to feed; `GROUP_TESTS` (:230). Sentinel.
- `intro_notification_orbit_route_test.dart` — returnTab restore, feed-resting only (MISSING orbit-resting → TC-214-06). AUTO glob.
- `post_notification_open_flow_test.dart` — forced `switchTo(feed)` on post opens. Sentinel. AUTO glob.
- `onboarding_golden_path_test.dart` — headless use-case journey, no navigation assertions; `OPTIONAL_MANUAL_TESTS` (:336). Not a landing lock.
- Sim tier: `intro_e2e_runner.dart` / `smoke_test_friends.sh` assert DB convergence, never the home surface. No sim asserts the landing (accepted, see Device/Relay Proof Profile).
Missing coverage gaps: normal-path root landing; landing-surface (tab) assertions on scan/accept; orbit-initial 163 pause; orbit-resting returnTab.
Already in curated family arrays?: BASELINE (startup_router_recovery, qr_scanner_wired), FEED (feed_wired, feed_swipe, feed_header, feed app_shell_controller), GROUP (orbit_wired + orbit chrome suite). `INTRO_TESTS` = introduction-FEATURE (friend-of-friend), NOT onboarding — do not put 214 tests there.

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)
1. `test/features/posts/phase1/app_shell_controller_test.dart::'defaults to orbit and accepts feed as a first-class tab'` (flip of existing test at line 7)
   - Tier: unit/application
   - Shape/setup: bare `AppShellController()`; also invalid-tab-id coercion cases in the same file.
   - RED on HEAD because: constructor default is `AppShellTab.feed` (`app_shell_controller.dart:22`); invalid ids also coerce to `feed` (:25-27).
   - GREEN after fix asserts: `activeTab == AppShellTab.orbit` on bare construction; invalid ids coerce to `orbit`; `initialTab: AppShellTab.feed` still honored (feed stays first-class).
   - Mutation that re-reds: revert `app_shell_controller.dart:22` (or :27) to `AppShellTab.feed` → red.
2. `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart::'5q: QR scan success without buffered intent lands on the Orbit surface'` (flip of `'…navigates to feed only'`)
   - Tier: widget
   - Shape/setup: existing 5q fixture (scan success → dialog OK); keep `find.byType(FeedWired)` findsOneWidget (shell root preserved — the stack-nuke discriminator) and ADD `controller.activeTab == AppShellTab.orbit` + `find.byType(OrbitWired)` findsOneWidget (embedded orbit host mounts at `FeedWired.initState` when tab==orbit, `feed_wired.dart:376`).
   - RED on HEAD because: activeTab stays at the `feed` default after OK (scanner never calls `switchTo` — verified 0 occurrences), so `OrbitWired` findsNothing.
   - GREEN after fix asserts: shell root + orbit tab + orbit host mounted.
   - Mutation that re-reds: revert the default → red. Also audit-and-flip the sibling `'contact QR success forwards Move Account runner into feed'` (prop-forwarding assertions stay; any Feed-surface assertion flips) and any "with buffered intent" variants that assert a Feed landing after `settleShareIntentFlow`.
   - Distinct-event discriminator: `FeedWired` present AND `OrbitWired` present AND `activeTab == orbit` — distinguishes "shell shows orbit" from both "pushed a different route" and "shell shows feed".
3. `test/features/home/presentation/screens/first_time_experience_wired_test.dart::'5o: accept success without buffered intent lands on the Orbit surface'` (flip of `'…navigates to feed only'`)
   - Tier: widget
   - Shape/setup: existing 5o fixture (incoming request → accept → success); assertions as in #2. Extend `'accept success forwards nearby dependencies into feed'` the same way (deps forwarding unchanged, landing assertion updated). Audit buffered-intent siblings as in #2.
   - RED on HEAD because: `_acceptRequest` pushes the shell with the `feed`-default controller (`first_time_experience_wired.dart:243-291`); orbit pane not mounted.
   - GREEN after fix asserts: shell root + `activeTab == orbit` + `OrbitWired` mounted; failure branch untouched (sibling test stays green: snackbar, no nav).
   - Mutation that re-reds: revert the default → red.
4. NEW `test/features/identity/presentation/screens/startup_router_home_surface_test.dart::'hasIdentityWithContacts cold start lands on the shell showing Orbit'`
   - Tier: widget
   - Shape/setup: pump `StartupRouter` with stored identity + contactCount ≥ 1 fakes (clone the fixture style of `startup_router_recovery_test.dart` / `startup_router_notification_open_test.dart`), bare `AppShellController()` threaded as production does; settle.
   - RED on HEAD because: no test today asserts the normal-path landing at all, and on HEAD the shell renders the Feed pane (`activeTab == feed`); the new assertion `OrbitWired` findsOneWidget fails.
   - GREEN after fix asserts: `FeedWired` is the root (first) route, `activeTab == AppShellTab.orbit`, `OrbitWired` mounted. Second case in same file: `'startup route event still emits ID_STARTUP_ROUTE_FEED for the shell'` (locks the flow-event name so log tooling doesn't silently break; green both sides — sentinel case).
   - Mutation that re-reds: revert the default → landing case red.
5. NEW `test/features/home/integration/onboarding_landing_surface_test.dart::'first-run journey: QR screen → first accept → Orbit surface'` — **PROD-CRITICAL**
   - Tier: integration (fake net, widget-pumped journey — the end-to-end landing proof; do NOT treat the unit row alone as sufficient)
   - Shape/setup: pump `StartupRouter` with identity + 0 contacts → assert `FirstTimeExperienceWired` visible; inject an incoming contact request through the fake repo/service (reuse `onboarding_golden_path_test.dart` fakes + 5o fixture wiring); accept; settle.
   - RED on HEAD because: journey terminates on the Feed pane (`activeTab == feed`, `OrbitWired` findsNothing).
   - GREEN after fix asserts: journey terminates on shell root + orbit tab + `OrbitWired` visible; conversation data intact (golden-path parity).
   - Mutation that re-reds: revert the default → red.
6. `test/features/push/application/intro_notification_orbit_route_test.dart::'orbit resting tab: intro route returns to orbit without a spurious switch'` (NEW test in existing file)
   - Tier: widget (sentinel — GREEN on HEAD when constructed with explicit `initialTab: AppShellTab.orbit`; guards what becomes the common case)
   - Shape/setup: controller explicitly on orbit; drive `openIntroNotificationOrbitRoute` open → pop.
   - RED on HEAD: N/A — sentinel by construction (mechanism confirmed self-adapting: guard `main.dart:3422` + same-tab early-return `app_shell_controller.dart:36-39`).
   - GREEN asserts: after pop, `activeTab == orbit`; no extra `switchTo` notification fired mid-route (listener count assertion).
   - Mutation that re-reds: change the finally-restore (`main.dart:3431-3432`) to hardcode `switchTo(AppShellTab.feed)` → red.
7. `test/features/feed/presentation/screens/feed_wired_test.dart::'cold start on orbit applies off-screen pause to the feed pane'` + `::'initial-orbit mount swipes back to feed'` (NEW tests in existing file)
   - Tier: widget
   - Shape/setup: pump `FeedWired` with `AppShellController(initialTab: AppShellTab.orbit)` (already legal — `feed_wired.dart:373-381` honors it); reuse the 163 pause probes and the existing right-swipe fixture.
   - RED on HEAD: to be determined at RED phase — these lock an invariant never exercised from an orbit-INITIAL mount. If red on HEAD, the initState pause/exit-registration wiring gap becomes an in-scope production fix (Stop-if below).
   - GREEN asserts: feed pane off-screen-paused at first frame on orbit; right swipe from initial orbit completes to feed (exit action registered → `_onClose` → `switchTo(feed)`).
   - Mutation that re-reds: remove the `_hasMountedOrbitHost` initState latch / swipe-controller seeding (`feed_wired.dart:376-381`) → both red.

## Test Coverage Matrix (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-214-01 default tab is orbit (+ invalid coercion) | pure logic | unit | posts/phase1/app_shell_controller_test.dart::'defaults to orbit and accepts feed as a first-class tab' | default is `feed` (app_shell_controller.dart:22,27) | revert :22/:27 to feed | `flutter test test/features/posts/phase1/app_shell_controller_test.dart` | AUTO (glob) |
| TC-214-02 post-QR-scan lands on Orbit | UI/widget nav | widget | qr_scanner_wired_test.dart::'5q: QR scan success without buffered intent lands on the Orbit surface' (+ Move-runner & buffered-intent sibling audit) | activeTab stays `feed` after OK; OrbitWired findsNothing | revert default → red | `./scripts/run_test_gates.sh baseline` | already in BASELINE_TESTS (run_test_gates.sh:10) |
| TC-214-03 post-first-accept lands on Orbit | UI/widget nav | widget | first_time_experience_wired_test.dart::'5o: accept success without buffered intent lands on the Orbit surface' (+ deps-forwarding & buffered-intent sibling audit) | pushReplacement shell renders feed pane | revert default → red | `./scripts/run_test_gates.sh baseline` | AUTO (glob) + **pin into BASELINE_TESTS** (214 comment) |
| TC-214-04 cold start w/ contacts lands on Orbit; shell stays first route; ID_STARTUP_ROUTE_FEED name locked | UI/widget nav + root invariant | widget | NEW startup_router_home_surface_test.dart::'hasIdentityWithContacts cold start lands on the shell showing Orbit' (+ flow-event sentinel case) | no normal-path landing lock exists; shell renders feed pane | revert default → red | `./scripts/run_test_gates.sh baseline` | AUTO (glob) + **pin into BASELINE_TESTS** (214 comment) |
| TC-214-05 full first-run journey FTE→accept→Orbit (**PROD-CRITICAL**) | multi-step flow, fake net | integration (widget-pumped) | NEW test/features/home/integration/onboarding_landing_surface_test.dart::'first-run journey: QR screen → first accept → Orbit surface' | journey ends on feed pane | revert default → red | `./scripts/run_test_gates.sh baseline` | AUTO (glob: features/<f>/integration auto-classifies) + **pin into BASELINE_TESTS** (214 comment) |
| TC-214-06 orbit-resting returnTab (intro-notif route) | UI/widget nav, sentinel | widget | intro_notification_orbit_route_test.dart::'orbit resting tab: intro route returns to orbit without a spurious switch' | N/A — sentinel, green on HEAD w/ explicit orbit initialTab (self-adapting mechanism confirmed) | hardcode feed restore at main.dart:3431 → red | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-214-07 orbit-initial mount: 163 pause + swipe-back | lifecycle invariant | widget | feed_wired_test.dart::'cold start on orbit applies off-screen pause to the feed pane' + ::'initial-orbit mount swipes back to feed' | TBD at RED phase (invariant never exercised from orbit-initial); if red → in-scope wiring fix | remove initState latch/seed feed_wired.dart:376-381 → red | `./scripts/run_test_gates.sh feed` | already in FEED_TESTS (run_test_gates.sh:182) |
| TC-214-08 preservation: orbit exits→feed; FTE failure stays; posts-notif forces feed | sentinels (existing) | widget | orbit_wired_test.dart (exit suite) · first_time_experience_wired_test.dart (failure branch) · post_notification_open_flow_test.dart | N/A — must stay GREEN both sides | delete orbit exit switchTo(feed) orbit_wired.dart:2356 → orbit_wired_test red (proves sentinel is live) | `./scripts/run_test_gates.sh groups` + `feed` + `feature-host-all` | already registered (GROUP_TESTS:230 / AUTO / AUTO) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-214-01 + TC-214-04 — the tab is deliberately in-memory; every process restart reconstructs `orbit` (a user who switched to Feed and restarts lands on Orbit — that IS the requested "Orbit is the main screen" behavior, locked by TC-214-04's bare-construction fixture). No persistence introduced → no reopen/migration row needed beyond these.
- **Sibling-surface consistency:** all "land home" surfaces enumerated and covered: cold start (TC-04), post-scan (TC-02), post-accept (TC-03), full journey (TC-05), intro-notif return (TC-06), posts-notif forced-feed asymmetry (deliberate + test-locked, TC-08), six `popUntil(isFirst)` sites (unchanged semantics — land on the shell's CURRENT tab; root-route invariant locked by TC-04's first-route assertion; Settings round-trip sentinel in feed_wired_test stays green).
- **Destructive-action side-effects:** justified N/A — no new/changed delete/cleanup path. The pre-existing `pushAndRemoveUntil` stack nuke is unchanged and still asserted (TC-02 keeps the shell-as-root assertion).
- **Invariant re-verification under new transitions:** orbit-INITIAL mount is the new state → TC-214-07 re-verifies the 163 off-screen-pause invariant and swipe-back exit registration from that state; TC-214-06 re-verifies returnTab restore under the new resting tab.

## Invariants (locked by tests)
- INV-214-1: bare-constructed `AppShellController` starts on orbit; invalid ids coerce to orbit; explicit `feed` still honored → TC-214-01.
- INV-214-2: all three landings render the Orbit surface while `FeedWired` remains the root shell (first route) → TC-214-02/03/04/05.
- INV-214-3: Feed stays reachable and Orbit exits land on Feed; FTE failure branch does not navigate; posts-notif still forces Feed → TC-214-08.
- INV-214-4: the hidden feed pane is off-screen-paused on orbit-initial mount; swipe-back works from first frame → TC-214-07.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot the dirty tree: `git status --short` (tree carries live UNCOMMITTED 211 work — orbit_screen/orbit_wired/feed_header/toggle-button files + 2 new orbit test files; do NOT revert or stage them).
2. Add/flip the RED tests (catalog §1-5, §7); run the focused RED commands (Acceptance Gates block) and confirm each fails for its documented reason. §7's two tests may be green on HEAD — record which.
3. Production edit (the single seam): `lib/features/feed/application/app_shell_controller.dart` — `:22` default `initialTab = AppShellTab.orbit`; `:27` coercion fallback `AppShellTab.orbit`; update the class doc comment. **No other production file changes.** Stop-if: any RED test still red after this edit for a mechanism reason (not fixture) → the landing path has an unverified `switchTo` — replan, do not patch call sites ad hoc.
4. Fixture triage (mechanical, test-only): `GRAPH_OK=1 grep -rn "AppShellController(" test/ | grep -v initialTab` (28 files today). Policy: suites that ARRANGE feed-first behavior (feed_wired_test feed-start swipe/scroll/bg cases, feed_swipe_test, feed_focus_test, feed_contract_preservation_test, feed_wired_bg_task_test, settings_wired round-trips, share/posts flows) pin `initialTab: AppShellTab.feed` explicitly; suites that TEST the default landing keep bare construction. orbit_wired_test's 22 bare sites are expected unaffected (exit tests force tabs); verify, don't blanket-pin. Stop-if: a suite is red for a non-tab reason → investigate separately, it is scope drift.
5. Registration: append `test/features/home/presentation/screens/first_time_experience_wired_test.dart`, `test/features/identity/presentation/screens/startup_router_home_surface_test.dart`, `test/features/home/integration/onboarding_landing_surface_test.dart` to `BASELINE_TESTS` in scripts/run_test_gates.sh with a `# 214` comment (repo convention). Add §6's sentinel to the existing intro_notification file (AUTO).
6. Rerun direct GREEN → preservation → named gates (block below), including `completeness-check`.
7. Graph maintenance: `graphify update .` from repo root AND `./graphify-arch/refresh_arch_graph.sh` (app-owned lib/ changed).
8. Manual sim smoke (closure evidence): boot two sims (check no live `/sims` sweep first — host-contention hazard; use `scripts/run_sims_detached.sh` conventions), create identity on A, send request from B, accept on A → screenshot must show the Orbit surface. Repeat for cold start (relaunch A) → Orbit.

## Risks And Edge Cases
- **Orbit pane pump-ability in the 5q/5o fixtures**: the embedded `OrbitWired` must render with those tests' fakes. `feed_wired_test` already pumps the orbit pane, so it is feasible; if a missing dep bites, assert `activeTab == orbit` + `find.byType(OrbitWired)` only (still red on HEAD) and skip deep orbit-chrome assertions. Use a wide pump surface (211 trap: sculpt bgPoint needs width). → pinned by TC-02/03.
- **Fixture-triage breadth** (~28 files): mechanical but wide; wrong blanket-pinning would mask real regressions. Policy in Step 4; preservation gates catch mistakes. → pinned by TC-08 + gate counts.
- **163 off-screen pause not engaging on orbit-initial mount** (feed timers running while hidden at cold start): possible latent gap, never exercised. → pinned by TC-214-07 (becomes in-scope fix if red).
- **Flow-event/log tooling assuming `ID_STARTUP_ROUTE_FEED`**: name deliberately kept (it means "shell route"); locked by TC-04's sentinel case.
- **Concurrent-session array edits**: BASELINE_TESTS pins may collide with another live session editing run_test_gates.sh (212 precedent: surgical index staging) — check for other live claude sessions on the shared tree before editing.
- **Pre-existing dirty-tree red**: `group_conversation_wired_bg_task_test` red predates 211/212 — not 214 scope.

## Device/Relay Proof Profile
host-only for closure + manual two-sim screenshot smoke (Step 8) as device evidence. Justification: the change crosses no OS boundary, no crypto, no relay, no multi-device convergence — it is pure in-app navigation state; the camera-driven QR scan leg cannot be automated on simulators, and the sim intro harness (`intro_e2e_runner.dart`) asserts DB state, not UI surface, by design. No feature flag involved. No DB migration (tab deliberately not persisted) → no `DB v##`.
Closure scenario: manual smoke per Step 8 (screenshot evidence attached to Execution Progress).
Deferred device work → none.

## Acceptance Gates (literal — copy/paste)
```bash
# 0. Dirty-tree snapshot (expect the 211-uncommitted set; record it)
git status --short

# 1. RED (before the production edit) — each must FAIL for the documented reason
flutter test test/features/posts/phase1/app_shell_controller_test.dart --plain-name 'defaults to orbit and accepts feed as a first-class tab'   # expect: 1 failing
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart --plain-name '5q: QR scan success without buffered intent lands on the Orbit surface'   # expect: 1 failing (OrbitWired findsNothing)
flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart --plain-name '5o: accept success without buffered intent lands on the Orbit surface'   # expect: 1 failing
flutter test test/features/identity/presentation/screens/startup_router_home_surface_test.dart   # expect: landing case failing, flow-event case passing
flutter test test/features/home/integration/onboarding_landing_surface_test.dart   # expect: 1 failing
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'cold start on orbit applies off-screen pause to the feed pane'   # record RED-or-GREEN on HEAD

# 2. Direct GREEN (after Step 3 + 4) — re-run every command above: all pass
flutter test test/features/posts/phase1/app_shell_controller_test.dart
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart
flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart
flutter test test/features/identity/presentation/screens/startup_router_home_surface_test.dart
flutter test test/features/home/integration/onboarding_landing_surface_test.dart
flutter test test/features/push/application/intro_notification_orbit_route_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart

# 3. Preservation sentinels + named gates (expect: zero new failures vs the step-0 baseline;
#    known pre-existing red: group_conversation_wired_bg_task_test — NOT 214)
./scripts/run_test_gates.sh baseline        # incl. the 3 newly pinned 214 files
./scripts/run_test_gates.sh feed            # baseline count 292 + TC-214-07 additions
./scripts/run_test_gates.sh groups          # baseline count 1110 (211 uncommitted additions included)
./scripts/run_test_gates.sh posts
./scripts/run_host_test_gates.sh feature-host-all

# 4. Registration / completeness (all new tests visible in a gate; no unclassified files)
./scripts/run_test_gates.sh completeness-check

# 5. Hygiene
flutter analyze            # 0 new issues
git diff --check

# 6. Graph maintenance (app-owned lib/ changed)
graphify update .
./graphify-arch/refresh_arch_graph.sh
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the six step-1 commands, each for its documented mechanism (feed-default landing).
- Pre-existing dirty: 211 uncommitted working-tree files (do not revert — live sibling work); `group_conversation_wired_bg_task_test` red predates this work.
- Environment blocker (NOT product): missing/booted-out simulators for Step 8 smoke; `/sims` host contention if a sweep is live.
- Scope drift (BLOCKING): any red outside the matrix rows + triage list — especially anything touching orbit exits, notification routing, or startup recovery.

## Done Criteria
- [ ] RED added first; each failed for its documented reason (TC-07 RED/GREEN-on-HEAD recorded).
- [ ] Single-seam edit only (`app_shell_controller.dart`); mutation-verified (revert → TC-01..05 red).
- [ ] Direct GREEN + preservation sentinels + named gates pass; zero new failures vs baseline.
- [ ] No DB change (verified: no migration files touched).
- [ ] Manual two-sim smoke screenshots show Orbit after accept AND after cold restart.
- [ ] 3 files pinned into BASELINE_TESTS; completeness-check green; `flutter analyze` 0 new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not persist the active tab (no keystore/DB/prefs write; no migration).
- Do not edit the three navigation call sites (`startup_router.dart:351-459`, `first_time_experience_wired.dart:243-291`, `qr_scanner_wired.dart:382-434`) — the seam is the controller default only.
- Do not redefine Orbit exit semantics (`orbit_wired.dart:2354-2380`, `feed_wired.dart:2446-2451` stay: exits → feed).
- Do not touch `openIntroNotificationOrbitRoute` (`main.dart:3410-3436`) or `PostNotificationOpenCoordinator._revealPosts` forced feed (`post_notification_open_coordinator.dart:126`).
- Do not rename `FeedWired`, `buildFeedSlideUpRoute`, or the `ID_STARTUP_ROUTE_FEED` flow event.
- Do not touch `OrbitViewMode` (innerCircle/allChats) or its deliberate non-persistence.
- Do not revert/stage the uncommitted 211 files; do not blanket-pin `initialTab: feed` in orbit_wired_test.

## Accepted Differences / Intentionally Out Of Scope
- Post-notification POSTS opens still force Feed (deliberate TestFlight design; locked by existing post_notification_open_flow_test).
- Share-intent detour landing is proven via TC-04 only: the detour's `onClose` pushes the **identical** `buildFeed` closure (`startup_router.dart:430-434`) — a separate ShareTargetPicker pump adds cost without a distinct seam; the buffered-intent siblings of 5q/5o (audited in TC-02/03) cover the post-settle landing.
- Existing users land on Orbit every cold start with no memory of their last tab — this is the requested behavior, not a gap.
- No registered simulator scenario for the FTE landing (camera QR not automatable on sims; DB-state intro sims unchanged); manual smoke is the device evidence.
- Slide-up transition + `buildFeedSlideUpRoute` name unchanged (cosmetic rename churn).

## Dependency Impact
- 211 (uncommitted, same tree): shares orbit chrome test files and the GROUP_TESTS array region — coordinate staging; 214 must not stage/commit 211 hunks.
- 209/196 (Orbit QR/Scan chrome): once Orbit is home, its QR/Scan entries become the primary add-contact affordances — no code dependency, product continuity only.
- Any future "persist last tab" request must revisit TC-214-01/04 (they lock always-orbit).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) run 2026-07-05: all core conditions + yes/no gates pass. Spec-case totality: 8 TCs, 8 matrix rows, no orphans. Every behavior-bearing edit (the default flip) is mutation-verified by 5 independent rows; sentinels (TC-06/08) carry their own mutations proving they are live. No vacuous coverage: TC-02 asserts the discriminating triple (shell root AND orbit host AND activeTab). Migration gate: N/A, no schema change. Boundary gate: no OS/crypto/relay boundary crossed; PROD-CRITICAL leg named (TC-05) + manual sim smoke. Registration: every new test AUTO-globbed AND the three landing suites pinned into BASELINE_TESTS; completeness-check is a literal gate. Blind-spot sweep: 2 rows (TC-04 restart-landing, TC-07 pause/swipe re-verification), 2 justified N/A (destructive actions; persistence). Weakest evidence: TC-07's RED-on-HEAD status is unknown until executed (explicitly recorded as TBD with a stop-if).

## Arbiter Decision
Structural blockers: none. Deferred details: TC-07 RED status resolved at execution; fixture-triage exact file list resolved by the Step-4 grep. Accepted differences: as listed. Verdict: plan is implementation-ready.

## Final Execution Verdict
Verdict: IMPLEMENTED host-green | Files changed: 1 production (app_shell_controller.dart), 14 test files flipped/pinned, 2 NEW test files, run_test_gates.sh (+3 BASELINE pins) | Tests run (+counts): baseline 131+2, feed 294, groups 1153, posts, settings 198, orbit 501, identity/share/home 290, completeness 1023/1023 — all PASS | Blocking: none | QA verdict: RED→GREEN verified per matrix row; TC-07 recorded GREEN-on-HEAD | Non-blocking follow-ups (owner): two-sim manual smoke deferred — shared tree mid-edit by concurrent 215/207 session at commit time (this session, when tree compiles); 215 chat-on-top interacts with TC-05's root-route assertion and must re-run the 214 landing suites when it lands (215 session)
