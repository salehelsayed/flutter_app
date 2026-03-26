# Session-by-Session TODO Roadmap 2

**Purpose:** Capture the remaining sessions that were still missing after `15-session-todo-roadmap.md`
**Use Model:** Same as roadmap 15: one session to plan a todo, one later session to execute it, with explicit file-entry points, existing tests, missing regressions, and minimum gates to run

---

## Executive Summary

`15-session-todo-roadmap.md` already covers the main high-value Flutter-tree work: named regression gates, feed inline reply durability, notification adapter tests, nearby-post rejection coverage, onboarding confidence, announcement happy path, posts schema-capability caching, identity caching, low-risk cleanup, and lightweight local timing counters.

This second roadmap covers the **remaining items that were still not fully scheduled**:

1. Turning named gates from local conventions into enforced CI / release automation
2. Closing the narrower announcement creation gap that still remains separate from the broader announcement happy path
3. Verifying or strengthening Go-side announcement writer enforcement evidence
4. Running the profile-gated UI performance follow-ups from report `04`
5. Running the deferred DB/storage follow-ups from report `05`
6. Addressing the medium-priority 1:1 operability items from report `08`
7. Extending the local observability work so it also covers decrypt-failure visibility and DB helper hotspots from report `10`

This roadmap is intentionally different from roadmap 15 in one important way:

- Several sessions here are **profile-gated** or **evidence-gated**
- For those sessions, a valid outcome is:
  - collect the trace / measurement,
  - conclude the code should remain as-is,
  - document why,
  - stop without speculative refactoring

That is still a completed session.

### Assumed Prerequisites

- If roadmap 15 Session 1 has **not** yet produced a canonical gate script / reference, Session 12 below must either:
  - start by executing roadmap 15 Session 1,
  - or narrow scope to the external CI wiring handoff only
- If roadmap 15 Session 11 has **not** yet landed the basic local timing layer, Session 23 below must reopen that work before extending it
- If a follow-on session discovers that roadmap 15 already closed the gap, update both roadmaps before continuing

---

## How To Use This Roadmap

### For a Planning Session

For each todo:

- Open the **Source Reports**
- Reopen the listed **Code / Repo Entry Points to Inspect First**
- Check whether a prerequisite from roadmap 15 has already landed
- Review the **Existing Tests to Reuse**
- Confirm whether the session is:
  - implementation-ready,
  - profile-gated,
  - or possibly stale
- Produce a plan that stays inside the listed scope

### For an Execution Session

For each todo:

- Reconfirm that the prerequisite sessions are done when required
- Add the listed regression first when the area is risky
- If the session is profile-gated, gather evidence before editing code
- Implement the smallest complete fix or measurement slice
- Run the **Direct Test Set**
- Run the **Subsystem Gate**
- Run the **Baseline Gate** when the session changes Flutter code
- Run the **Startup / Transport Gate** only when the change affects bootstrap, resume, transport fallback, DB-open startup, or device-backed media flows

### Global Testing Rules

| Rule | Meaning |
|------|---------|
| **Profile before optimizing profile-gated work** | Static inspection alone is not enough for sessions derived from report `04` or profile-only items from report `05` |
| **If the data says “do nothing,” stop** | A profile session is successful if it proves the current code is already good enough |
| **Cross-tree sessions must verify contracts, not just code existence** | A Go-side or CI-side session is only complete when the contract is demonstrably enforced |
| **Prefer the smallest proving layer first** | Unit / helper / deterministic integration tests first, then device-backed or Go-tree tests when the contract actually lives there |
| **Do not let observability work become exporter work** | Local counters, timers, and snapshots first; dashboards/exporters remain deferred |
| **One missing contract = one stable entry point in the roadmap** | Keep follow-on sessions narrow so future planning does not have to rediscover the files or tests involved |

---

## Roadmap Order

| # | Todo | Why It Comes Now | Main Risk if Skipped | Main Gate |
|---|------|------------------|----------------------|-----------|
| 12 | Wire named test gates into CI / release automation | Session 1 of roadmap 15 defines gates locally; this makes them team-enforced instead of advisory | Gates drift, naming diverges, and risky changes can still merge without the intended suites | Gate script validation + CI path |
| 13 | Add announcement-specific create-group regression | Session 6 from roadmap 15 covers the happy path, but create-group itself is still too chat-weighted | Announcement creation can remain only indirectly proven | Group Messaging |
| 14 | Verify / strengthen Go-side announcement writer enforcement | Flutter-side announcement behavior is already stronger; the remaining auth evidence gap lives in Go / bridge code | Admin/member write rules may look covered in Dart while server/validator behavior remains ambiguous | Go node / bridge tests |
| 15 | Profile Orbit painter cost and optimize only if hot | This is the smallest isolated UI perf follow-up and has no other preconditions | Time gets wasted on paint speculation or the real hotspot stays unknown | Orbit widget suite + captured trace |
| 16 | Profile FeedWired init churn and batch only if measured | Feed has a real but small init-churn candidate and already has strong wired tests | Startup churn discussions stay speculative or lead to noisy refactors | Feed / Surface |
| 17 | Profile ConversationWired subscription cost and trim only if measured | Conversation lifecycle complexity is risky and should be touched only after evidence | Off-screen churn may remain invisible, or lifecycle code may get overengineered without data | 1:1 Reliability if code changes |
| 18 | Reduce repeated single-post lookups in pinned / one-by-one hydration paths | This is the next DB/storage item after schema-capability caching and identity caching | Heavy post queries keep getting re-run in narrow but real loops | Posts / Privacy |
| 19 | Profile targeted recovery/download indexes and add only if justified | Index work should happen only after the clearer DB wins are done | Premature migrations add complexity without payoff, or a real scan issue stays unmeasured | 1:1 Reliability if schema changes |
| 20 | Revisit reload-after-update message rebroadcasts | This is narrower than index work and stays inside one repository boundary | Avoidable DB reads remain on status-update paths | 1:1 Reliability + Feed / Surface |
| 21 | Surface V2 decryption failures more clearly | This is the next medium-priority 1:1 correctness / operability follow-up after durable send parity | Messages can still disappear too quietly when decryption fails | 1:1 Reliability |
| 22 | Add media download deduplication / in-flight guard | This is the other medium-priority 1:1 operability follow-up from report `08` | Multiple callers can still race the same attachment download | 1:1 Reliability |
| 23 | Extend local observability with decrypt-failure counters and DB hotspot probes | Session 11 from roadmap 15 adds the basic timing layer; this finishes the still-missing local signals from report `10` | Debugging remains blind on decrypt pain points and heavy DB helpers | Area-specific suites + Baseline |

---

## Session 12: Wire Named Test Gates Into CI / Release Automation

**Goal:** Turn the named gates from roadmap 15 into an actually enforced workflow, not just a local convention, while still allowing a complete local handoff if the real external CI / release host is not accessible from the current workspace.

**Source Reports**
- `14-regression-test-strategy.md`
- `15-session-todo-roadmap.md`
- `session-1-plan.md`

**Code / Repo Entry Points to Inspect First**
- `scripts/run_test_gates.sh` if roadmap 15 Session 1 already created it
- `Test-Flight-Improv/test-gate-definitions.md` as the intended canonical markdown source of truth if it already exists
- `Test-Flight-Improv/test-gates-reference.md` if roadmap 15 Session 1 already created it
- `Test-Flight-Improv/session-1-plan.md`
- `scripts/check_push_release_gate.sh`
- `dart_test.yaml`
- Any actual CI / PR / release config the team uses outside this tree
  - There is currently no repo-local `.github/workflows/*` file in this Flutter tree, so the planning session must confirm where CI wiring really lives before implementation

**External Dependency Note**
- This session can be blocked by an external CI / release host that is not visible from the current workspace
- That is a **soft external dependency blocker**, not automatically a roadmap-stopping blocker
- If the real CI host or owner path cannot be reached, the session should switch into a local handoff outcome instead of failing outright
- In that fallback mode, the session should:
  - reconcile the local gate runner and gate-definition artifacts,
  - document the exact commands CI should invoke,
  - record the missing external repo / path / owner explicitly,
  - and stop without pretending the external wiring has landed

**Existing Tests to Reuse**
- The canonical gate file lists from `14-regression-test-strategy.md`
- The gate-script contract described in `session-1-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md` if it already exists
- The existing release-style shell-script pattern in `scripts/check_push_release_gate.sh`

**Regression To Add First**
- None required if this stays script / docs / CI-wiring only
- If the gate runner exists but has ambiguous naming, resolve the mismatch first
  - `session-1-plan.md` uses `transport`
  - `14-regression-test-strategy.md` uses `startup_transport`

**Direct Test Set**
- Run the gate script end-to-end once it exists:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh posts`
  - the chosen transport command, with device when required
- If an external CI file is changed, validate that the command it runs matches the canonical gate script exactly
- If the external CI host is not accessible, validate that the handoff artifact names the same canonical commands and does not drift from the local runner / definition files

**Subsystem Gate**
- Not a feature-specific subsystem gate
- This session should validate the gate runner itself

**Baseline Gate**
- Yes
- In practice this session is about making Baseline and subsystem gates canonical

**Startup / Transport Gate**
- Yes, but only for validating the transport gate invocation path if that gate is wired through automation

**Done When**
- There is one canonical gate runner command surface
- There is one canonical markdown definition / reference artifact for the named gates
- One of these is true:
  - the CI / release path the team actually uses invokes the named gates instead of retyping ad-hoc `flutter test` commands,
  - or the repo contains a complete local handoff package for the external CI / release owner, including:
    - the canonical gate commands,
    - the expected invocation points,
    - the unresolved external repo / path / owner,
    - and any transport-gate device invocation notes
- Gate naming is consistent between:
  - report `14`,
  - roadmap `15`,
  - `test-gate-definitions.md`,
  - the script,
  - and the CI job definition when that job is accessible
- Future sessions can say “run the Group Messaging Gate” or “run the 1:1 Reliability Gate” and mean the exact same automated command everywhere

**Scope Guard**
- Do not invent a much larger CI matrix
- Do not replace named gates with broad directory sweeps unless a gate definition is intentionally being changed
- Do not silently assume GitHub Actions if the team’s real CI lives elsewhere
- Do not mark the session failed purely because the external CI / release host is inaccessible once the repo-local command surface and handoff package are complete

---

## Session 13: Add Announcement-Specific Create-Group Regression

**Goal:** Close the narrower Flutter-tree gap that announcement creation itself is not tested explicitly enough.

**Source Reports**
- `01-unit-test-coverage.md`
- `13-announcement-use-case-audit.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/presentation/screens/create_group_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/create_group_screen.dart`
- `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`

**Existing Tests to Reuse**
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/create_group_screen_test.dart`
- `test/features/groups/presentation/create_group_picker_screen_test.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/group_type_badge_test.dart`
- `test/features/groups/domain/models/group_model_test.dart`
- `test/core/database/helpers/groups_db_helpers_test.dart`

**Regression To Add First**
- At minimum, extend the create-group coverage so `GroupType.announcement` is explicitly proven through the creation path
- The regression should prove:
  - the submitted type is `announcement`
  - the created `GroupModel` stays `announcement`
  - persisted / mapped type remains `announcement`
  - the admin role and creation metadata still behave correctly
- If the UI flow can preselect announcement creation, the regression should also prove that route / picker state survives into the final create call

**Direct Test Set**
- `flutter test test/features/groups/application/create_group_use_case_test.dart`
- `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart`
- `flutter test test/features/groups/presentation/create_group_screen_test.dart`
- `flutter test test/features/groups/presentation/create_group_picker_screen_test.dart`
- `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart`
- `flutter test test/features/groups/presentation/group_type_badge_test.dart`

**Subsystem Gate**
- Group Messaging Gate

**Baseline Gate**
- Yes

**Done When**
- The Flutter tree has a direct, easy-to-find regression that proves announcement creation specifically
- A future reader no longer has to infer announcement creation correctness from chat-heavy tests plus broader happy-path evidence

**Scope Guard**
- Do not drift into the broader create -> send -> read -> react flow from roadmap 15 Session 6
- Do not broaden into Go-side announcement auth work here
- Do not add new announcement product features

---

## Session 14: Verify / Strengthen Go-Side Announcement Writer Enforcement

**Goal:** Close the remaining announcement-auth evidence gap at the Go / bridge layer.

**Source Reports**
- `09-network-group-messaging.md`
- `13-announcement-use-case-audit.md`

**Cross-Repo Note**
- This session is intentionally cross-tree
- The relevant code lives under `go-mknoon/`, not only under `lib/`
- The planning session must first decide whether the work is:
  - a real missing regression,
  - only a missing stronger bridge-level proof,
  - or already sufficiently covered and therefore stale

**Code / Repo Entry Points to Inspect First**
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/rendezvous_test.go`
- `go-mknoon/node/group.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/bridge_group_helpers.dart` only if the Go-side contract change affects Flutter-facing payloads

**Existing Tests to Reuse**
- Existing announcement / writer checks already present in:
  - `go-mknoon/node/pubsub_test.go`
  - `go-mknoon/node/rendezvous_test.go`
- Flutter-side announcement behavior tests from roadmap 15 Sessions 6 and 13, only as contract context

**Regression To Add First**
- First answer this exact question: do the current Go tests already prove the missing contract strongly enough?
- If not, add one explicit regression that proves:
  - a non-admin publish in an announcement group is rejected at the Go-side validator / publish path
  - the rejection happens before the message is treated as accepted / delivered
  - an admin publish in the same scenario is still accepted
- If the current tests already prove this clearly, the session should instead:
  - document that the roadmap item is stale,
  - and tighten only the missing bridge-level or package-level evidence if any remains

**Direct Test Set**
- `cd go-mknoon && go test ./node`
- `cd go-mknoon && go test ./bridge`
- If Flutter bridge payloads or contracts changed, also run:
  - `flutter test test/features/groups/application`
  - `flutter test test/features/groups/presentation`

**Subsystem Gate**
- Group Messaging Gate only if a Flutter-visible group contract changed

**Baseline Gate**
- Only if this session also changes Flutter code

**Startup / Transport Gate**
- Run if bridge contract changes affect group startup / rejoin / resume behavior

**Done When**
- The Go tree has clear, direct evidence that announcement writer enforcement is not merely a Flutter-side UI rule
- A future audit no longer has to say “this cannot be verified from the Flutter tree” without immediately pointing to the Go proof

**Scope Guard**
- Do not add announcement UX features here
- Do not broaden into scheduled announcements, read receipts, search, or admin tooling
- Keep the session about enforcement evidence, not product scope

---

## Session 15: Profile Orbit Painter Cost And Optimize Only If Hot

**Goal:** Confirm whether Orbit painter work is actually hot before touching the rendering code.

**Source Reports**
- `04-ui-performance.md`

**Code Files to Inspect First**
- `lib/features/orbit/presentation/widgets/orbital_ring_painter.dart`
- `lib/features/orbit/presentation/widgets/overflow_badge.dart`
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`

**Existing Tests to Reuse**
- `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
- `test/features/orbit/presentation/widgets/overflow_badge_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

**Profiling Evidence To Capture**
- Route-open and route-close traces for Orbit on a real device or representative simulator
- Whether `OrbitalRingPainter` or `_DashedBorderPainter` actually appear on the paint / raster hot path
- Whether the delayed `OverflowBadge` animation changes the cost materially
- Paint / raster timing before any edit

**Regression To Add First**
- None required for profiling-only work
- If optimization is justified, add the smallest test that protects visual behavior first
  - for example, widget tests around Orbit visualization / overflow badge rendering

**Direct Test Set**
- `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
- `flutter test test/features/orbit/presentation/widgets/overflow_badge_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- Any temporary local profile harness or trace-capture command used during the session

**Subsystem Gate**
- No named subsystem gate unless Orbit code actually changes

**Baseline Gate**
- Optional for pure profiling
- Yes if any production code changes

**Done When**
- There is a clear answer to whether these painters deserve optimization
- If the answer is “no”, the evidence is captured and the session ends without speculative cleanup
- If the answer is “yes”, the change is narrowly scoped and backed by before/after evidence

**Scope Guard**
- Do not redesign the Orbit UI
- Do not optimize painter code just because the loops look expensive in isolation
- Keep readability-only cleanup such as `pi` replacement secondary unless nearby code is already being touched

---

## Session 16: Profile FeedWired Init Churn And Batch Only If Measured

**Goal:** Confirm whether `FeedWired` initialization is causing meaningful route churn before batching state updates.

**Source Reports**
- `04-ui-performance.md`
- `15-session-todo-roadmap.md` if Sessions 3 or 9 changed feed / identity behavior

**Code Files to Inspect First**
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/settings/application/image_quality_preference_use_cases.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart` only if Session 9 from roadmap 15 already changed identity caching

**Existing Tests to Reuse**
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_bg_task_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`
- `integration_test/feed_performance_test.dart`

**Profiling Evidence To Capture**
- Number and timing of init-phase local state updates from:
  - `_loadIdentity()`
  - `_loadQualityPreference()`
  - `_loadVideoQualityPreference()`
  - `_loadFeedFromDatabase()`
  - `_loadTotalUnreadCount()`
- First-route frame timing before any batching
- Whether identity cache work from roadmap 15 Session 9 already removed most of the visible churn

**Regression To Add First**
- None required if this stays measurement-only
- If batching / sequencing changes are justified, add a focused test first that protects:
  - initial loading behavior,
  - first visible data state,
  - and non-regression of feed reply / unread / route state

**Direct Test Set**
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_bg_task_test.dart`
- `flutter test test/features/feed/integration`
- `flutter test integration_test/feed_performance_test.dart -d <device>` when device-backed timing validation is part of the session

**Subsystem Gate**
- Feed / Surface Gate

**Baseline Gate**
- Optional for pure profiling
- Yes if production code changes

**Done When**
- There is measured evidence for either:
  - leaving `FeedWired` as-is,
  - or applying a narrow batching / sequencing cleanup
- If a cleanup lands, first-route behavior and feed correctness remain unchanged

**Scope Guard**
- Do not mix this with durable-send parity work from roadmap 15 Session 3
- Do not redesign feed state management broadly
- Keep this strictly about init-time churn

---

## Session 17: Profile ConversationWired Subscription Cost And Trim Only If Measured

**Goal:** Confirm whether `ConversationWired` keeps enough off-screen or lifecycle cost to justify refactoring its subscriptions.

**Source Reports**
- `04-ui-performance.md`
- `08-network-1to1-messaging.md` when lifecycle or listener changes touch shared 1:1 behavior

**Code Files to Inspect First**
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `lib/core/media/audio_recorder_service.dart`

**Existing Tests to Reuse**
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/lifecycle/handle_app_resumed_stuck_sending_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`

**Profiling Evidence To Capture**
- Open / idle / background / foreground traces for the conversation route
- Whether `_incomingSubscription`, `_repoChangeSubscription`, `_contactUpdateSubscription`, `_reactionSubscription`, `_durationSub`, or `_amplitudeSub` are producing meaningful off-screen cost
- Whether recorder subscriptions only exist during active recording as expected
- Any frame or CPU cost attributable to the conversation route after it is no longer visible

**Regression To Add First**
- None required for profiling-only work
- If the session changes subscription ownership or cancellation behavior, add the smallest lifecycle regression first
  - especially around dispose, background, foreground, and active recording transitions

**Direct Test Set**
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `flutter test test/core/lifecycle`

**Subsystem Gate**
- 1:1 Reliability Gate if any production code changes touch listener / send / lifecycle behavior

**Baseline Gate**
- Optional for profiling-only work
- Yes if production code changes

**Startup / Transport Gate**
- Run if the session changes pause / resume or reconnect behavior

**Done When**
- There is clear evidence whether the current subscription model is acceptable
- If a refactor is justified, it is narrow, measured, and keeps message, reaction, recorder, and lifecycle behavior intact

**Scope Guard**
- Do not redesign conversation architecture wholesale
- Do not add lifecycle complexity just because multiple subscriptions exist
- Keep the change about measured subscription cost only

---

## Session 18: Reduce Repeated Single-Post Lookups In Pinned / One-By-One Hydration Paths

**Goal:** Remove the narrower repeated `getPost()` / single-post load loops that still amplify the heavy post query.

**Source Reports**
- `05-database-storage-performance.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/posts/application/load_pinned_posts_use_case.dart`
- `lib/features/posts/domain/repositories/post_repository.dart`
- `lib/features/posts/domain/repositories/post_repository_impl.dart`
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/features/posts/application/post_surface_hydrator.dart`
- `lib/features/posts/presentation/screens/posts_wired.dart`
- `lib/features/posts/application/post_notification_open_coordinator.dart`
- Any other obvious call sites that still do one-by-one `postRepo.getPost(...)` loops discovered during code review

**Existing Tests to Reuse**
- `test/features/posts/phase5/load_pinned_posts_use_case_test.dart`
- `test/features/posts/phase5/handle_incoming_post_pins_use_case_test.dart`
- `test/features/posts/phase5/posts_wired_pinned_section_test.dart`
- `test/features/posts/improvement/post_pin_remove_delivery_integration_test.dart`
- `test/features/posts/improvement/post_delivery_runner_test.dart`

**Regression To Add First**
- Add a focused regression that proves the chosen pinned / hydration path no longer depends on avoidable one-by-one post fetches
- The regression can be at:
  - use-case level with a counting fake repository,
  - repository level with a new bulk-load contract,
  - or helper level if a batch helper is introduced
- Preserve current behavior for:
  - dismissed pins,
  - ordering,
  - hydration,
  - and missing-post tolerance

**Direct Test Set**
- `flutter test test/features/posts/phase5`
- `flutter test test/features/posts/improvement`
- `flutter test test/features/posts`

**Subsystem Gate**
- Posts / Privacy Gate

**Baseline Gate**
- Yes

**Done When**
- The pinned / one-by-one hydration path no longer re-runs the heavy single-post query more often than necessary
- Behavior remains identical from the user’s point of view
- No broad SQL architecture rewrite was introduced

**Scope Guard**
- Do not build a materialized view here
- Do not introduce generic project-wide query caches
- Keep the session about obvious repeated single-post loops only

---

## Session 19: Profile Targeted Recovery / Download Indexes And Add Only If Justified

**Goal:** Decide whether the two remaining plausible index candidates are actually worth a migration.

**Source Reports**
- `05-database-storage-performance.md`
- `10-network-measurement-strategy.md`

**Code Files to Inspect First**
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/database/migrations/`
- `lib/main.dart` if the DB version / migration chain changes

**Candidate Indexes From The Report**
- `messages(status, is_incoming, timestamp)`
- `media_attachments(download_status)`

**Existing Tests to Reuse**
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart`
- `test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`

**Profiling Evidence To Capture**
- Whether recovery queries over `messages` actually scan enough rows to justify an index
- Whether download-status scans over `media_attachments` show up in real traces
- Query plans or call frequency before adding any migration

**Regression To Add First**
- None if the session ends as “profile only, no migration”
- If an index is justified, add the migration / schema assertion first
  - and make sure the migration test proves the index exists in the expected schema state

**Direct Test Set**
- `flutter test test/core/database/helpers/messages_db_helpers_test.dart`
- `flutter test test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart`
- `flutter test test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart`
- `flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`
- `flutter test test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `flutter test test/features/conversation/integration/media_attachment_flow_test.dart`

**Subsystem Gate**
- 1:1 Reliability Gate if the schema or helpers change

**Baseline Gate**
- Optional for profile-only work
- Yes if a migration or helper code changes

**Startup / Transport Gate**
- Run if the DB version or migration chain changes

**Done When**
- There is explicit evidence for one of two outcomes:
  - neither index is worth adding now,
  - or one / both indexes are justified and landed with migration coverage

**Scope Guard**
- Do not add broad “index all foreign keys” work
- Do not move into generic DB tuning beyond these two candidates
- If profiling does not justify the index, stop

---

## Session 20: Revisit Reload-After-Update Message Rebroadcasts

**Goal:** Remove the avoidable row reload after status updates if it can be done without weakening UI updates.

**Source Reports**
- `05-database-storage-performance.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

**Existing Tests to Reuse**
- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_stuck_sending_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`

**Regression To Add First**
- Add a repository-level regression that proves status transitions still emit the correct updated message shape
- The regression should be explicit about:
  - how many DB reads happen,
  - whether the updated message is emitted exactly once,
  - and whether consumers still receive the fields they need

**Direct Test Set**
- `flutter test test/features/conversation/domain/repositories`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `flutter test test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`

**Subsystem Gate**
- 1:1 Reliability Gate
- Feed / Surface Gate if feed-visible status updates are affected

**Baseline Gate**
- Yes

**Done When**
- The repository no longer performs an unnecessary “update then immediate reload” cycle purely to rebroadcast
- Downstream UI behavior remains unchanged

**Scope Guard**
- Do not redesign the message repository or thread summary model
- Keep the session about the rebroadcast path after updates

---

## Session 21: Surface V2 Decryption Failures More Clearly

**Goal:** Make incoming 1:1 decryption failures observable and intentionally handled instead of quietly disappearing into generic “not chat” behavior.

**Source Reports**
- `08-network-1to1-messaging.md`
- `10-network-measurement-strategy.md`

**Code Files to Inspect First**
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart` as a nearby comparison for decryption-failure semantics

**Existing Tests to Reuse**
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`

**Regression To Add First**
- Add explicit decryption-failure tests for both:
  - bridge decrypt returning `ok: false`
  - bridge decrypt throwing
- The regression should prove the failure is:
  - classified,
  - logged / surfaced through the chosen local observability path,
  - and not mistaken for an unrelated non-chat message

**Direct Test Set**
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- `flutter test test/core/inbox/inbox_round_trip_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`

**Subsystem Gate**
- 1:1 Reliability Gate

**Baseline Gate**
- Yes

**Done When**
- V2 decrypt failures are visible enough for debugging and local operability
- The code distinguishes decryption failures from benign “not my message / not chat message” outcomes
- Successful decrypt / receive behavior remains unchanged

**Scope Guard**
- Do not build user-facing crypto settings or receipt features
- Do not redesign the envelope format
- Keep this about failure handling and visibility only

---

## Session 22: Add Media Download Deduplication / In-Flight Guard

**Goal:** Prevent multiple callers from racing the same attachment download.

**Source Reports**
- `08-network-1to1-messaging.md`
- `10-network-measurement-strategy.md`

**Code Files to Inspect First**
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/posts/application/download_post_media_use_case.dart` to decide whether the same dedup pattern should be shared
- `lib/core/media/media_file_manager.dart`
- A small new helper such as `lib/core/media/download_coordinator.dart` if a shared in-flight guard is introduced

**Existing Tests to Reuse**
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- Post-media tests only if the implementation is shared with posts

**Regression To Add First**
- Add a concurrency regression that proves multiple overlapping requests for the same blob / attachment:
  - trigger only one real download,
  - converge on the same DB state,
  - and do not leave `download_status` oscillating incorrectly
- If a shared coordinator also covers posts, add one posts-side regression too

**Direct Test Set**
- `flutter test test/features/conversation/application/download_media_use_case_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- `flutter test test/features/conversation/integration/media_attachment_flow_test.dart`
- `flutter test test/features/conversation/integration/voice_message_exchange_test.dart`
- Relevant post-media direct tests only if the coordinator is shared

**Subsystem Gate**
- 1:1 Reliability Gate
- Posts / Privacy Gate only if post download code is touched

**Baseline Gate**
- Yes

**Startup / Transport Gate**
- Only if the bridge media-download contract changes

**Done When**
- Duplicate callers no longer race the same attachment download
- Success, failure, and cleanup paths remain correct
- The change stays small and local

**Scope Guard**
- Do not redesign lazy download policy
- Do not broaden into auto-download product settings
- Keep the implementation to an in-flight guard / coordinator, not a larger media subsystem rewrite

---

## Session 23: Extend Local Observability With Decrypt-Failure Counters And DB Hotspot Probes

**Goal:** Finish the still-missing local observability pieces from report `10` without building exporter / dashboard architecture.

**Source Reports**
- `10-network-measurement-strategy.md`
- `08-network-1to1-messaging.md`
- `05-database-storage-performance.md`
- `15-session-todo-roadmap.md` Session 11 if the basic timing layer was introduced there

**Code / Repo Entry Points to Inspect First**
- Reopen roadmap 15 Session 11 output first
  - `lib/core/observability/timing_probe.dart` if it exists
  - `lib/core/observability/session_metrics.dart` if it exists
- Existing local instrumentation:
  - `lib/core/utils/flow_event_emitter.dart`
  - `lib/core/utils/startup_timing.dart`
- Candidate measurement points:
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/application/download_media_use_case.dart`
  - `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
  - `lib/core/database/helpers/posts_db_helpers.dart`

**Existing Tests to Reuse**
- `test/core/utils/flow_event_emitter_test.dart`
- Conversation application tests touched by the instrumentation points
- Posts helper tests touched by DB timing probes
- Any observability tests added by roadmap 15 Session 11, if they already exist

**Regression To Add First**
- If the timing / metrics layer already exists:
  - add unit tests that prove new counters / timers are side-effect free
  - add tests for any local debug snapshot / dump output if introduced
- If roadmap 15 Session 11 is not yet implemented, stop and reopen that session first

**Direct Test Set**
- `flutter test test/core/utils/flow_event_emitter_test.dart`
- Area-specific direct tests for every instrumented conversation file
- Area-specific direct tests for every instrumented posts helper / repository file

**Subsystem Gate**
- 1:1 Reliability Gate if conversation instrumentation changed behavior boundaries
- Posts / Privacy Gate if posts helper timing probes changed helper behavior

**Baseline Gate**
- Yes

**Startup / Transport Gate**
- Run if this session adds probes in startup / resume / transport code instead of only local use cases

**Done When**
- The local observability layer includes:
  - decrypt-failure counters or equivalent local signals
  - retry-outcome visibility if touched
  - DB helper hotspot timings such as `db.posts.load` or the equivalent chosen helper names
  - optional local snapshot / dump output for debugging
- No exporter, dashboard, alerting, privacy-sampling, or analytics-backend architecture has been introduced

**Scope Guard**
- Do not build remote analytics export
- Do not build dashboards or alerting rules yet
- Keep the output local, developer-facing, and removable

---

## Future Session Prompt Template

When starting a future planning session from this file, use this structure:

```text
Open Test-Flight-Improv/16-session-todo-roadmap-2.md and plan Session <N>.
Read the listed source reports and code-entry files first.
Also confirm whether any prerequisite from Test-Flight-Improv/15-session-todo-roadmap.md is already done.
Do not implement yet.
Tell me:
1. what the real scope is,
2. whether the session is implementation-ready, profile-gated, or stale,
3. which files you need to inspect next,
4. what regression or tests must exist first,
5. what you would change,
6. which direct tests and gates you would run after implementation.
```

When starting a future execution session from this file, use this structure:

```text
Execute Session <N> from Test-Flight-Improv/16-session-todo-roadmap-2.md.
Follow the scope guard.
If the session is profile-gated, capture evidence before editing code.
Add the listed regression first if required.
Then implement the change and run the direct suite, subsystem gate, and baseline gate.
```

---

## Final Rules

- Treat roadmap 15 as the primary backlog for the already-identified P0 / near-P0 Flutter work
- Treat this roadmap as the follow-on backlog for the still-open residual items
- Prefer evidence-backed conclusions over speculative optimization
- If a session depends on a missing artifact from roadmap 15, reopen that prerequisite before continuing
- If a session turns out to be stale because the repo already covers the gap, update the roadmap instead of blindly implementing
- Keep cross-tree Go work and Flutter-tree work clearly separated unless a contract change truly crosses both

---

## Verdict

**This roadmap is the missing follow-on layer after roadmap 15.** It covers the items that were still partial, deferred, externalized, or evidence-gated: CI enforcement, the narrower announcement creation gap, Go-side auth proof, deferred UI and DB follow-ups, medium 1:1 operability items, and the remaining local observability signals. Used together with roadmap 15, it should let a future session reopen any remaining gap with the right reports, files, tests, and scope boundaries already in hand.
