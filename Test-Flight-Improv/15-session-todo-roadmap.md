# Session-by-Session TODO Roadmap

**Purpose:** Turn the current reports into an execution order that is safe, testable, and easy to revisit across separate sessions
**Use Model:** One session to plan a todo, one later session to execute it, with explicit file-entry points and test gates for each step

---

## Executive Summary

The reports under `Test-Flight-Improv/` already identify the important work. What is still missing is a **working order** and a **repeatable handoff format** for future sessions.

This roadmap solves that by giving each todo:

1. A clear goal
2. The reports to reopen first
3. The code files to inspect before planning
4. The tests that already protect the area
5. The regressions still missing
6. The minimum test gates to run after the change
7. A concrete “done” definition

The intended workflow is:

1. Start a session with one todo from this file
2. Read the listed reports and code-entry files
3. Produce a focused implementation plan
4. In a later session, execute the plan
5. Run the listed direct tests, subsystem gate, and baseline gate

---

## How To Use This Roadmap

### For a Planning Session

For each todo:

- Open the **Source Reports**
- Read the **Code Files to Inspect First**
- Review the **Existing Tests to Reuse**
- Confirm the **Regression to Add First** if the area is risky
- Produce a plan that stays inside the listed scope

### For an Execution Session

For each todo:

- Implement the smallest complete fix or feature slice
- Add the planned regression or targeted tests first when possible
- Run the **Direct Test Set**
- Run the **Subsystem Gate**
- Run the **Baseline Gate**
- Run the **Startup / Transport Gate** only when the change affects bootstrap, resume, transport fallback, or device-backed media behavior

### Global Testing Rules

| Rule | Meaning |
|------|---------|
| **Regression first for risky changes** | If a fix touches shared behavior, write the failing regression before changing the code |
| **One escaped bug = one permanent test** | Every production bug should leave behind a test that reproduces it |
| **Use the smallest proving layer first** | Prefer unit/use-case or deterministic integration tests before device-backed tests |
| **Do not replace subsystem gates with generic smoke** | Smoke is broad confidence, not deep pipeline protection |
| **If a send path is shared, test all payloads that use it** | Text-only coverage is not enough for media/voice-capable paths |

### Review Exit Rule

Use a bounded review loop, not an open-ended one:

1. planner writes the plan
2. reviewer critiques it
3. arbiter decides whether any findings are still structural blockers

Stop once the arbiter finds no new structural category of missing work. Additional individual files or alternate gate placements are not enough reason to keep looping.

---

## Roadmap Order

| # | Todo | Why It Comes Now | Main Risk if Skipped | Main Gate |
|---|------|------------------|----------------------|-----------|
| 1 | Formalize baseline + subsystem gates and classify unassigned tests | Creates the safety net before deeper changes | Future sessions run inconsistent tests and silently omit important suites | Baseline + docs/scripts |
| 2 | Add feed inline reply durable-send regression | Locks down the clearest current 1:1 gap | Reliability fixes can still re-break feed send | 1:1 Reliability + Feed / Surface |
| 3 | Fix durable send-path parity between conversation and feed inline reply | Highest-value correctness fix in current reports | Feed replies remain more crash-sensitive than conversation sends | 1:1 Reliability + Feed / Surface |
| 4 | Add notification adapter boundary tests | Covers a real boundary still lighter than domain tests | Notification routing/regression can slip through | Direct notification suite + Baseline |
| 5 | Add post presence rejection matrix | Protects privacy/freshness edge cases | Malformed or stale nearby presence can regress silently | Posts / Privacy |
| 6 | Add announcement-specific happy-path regression | Makes announcement coverage easier to trust in one place | Coverage stays fragmented and harder to reason about | Group Messaging |
| 7 | Add onboarding golden path | Adds one top-to-bottom confidence flow | Broad onboarding regressions stay distributed across many files | Contact / onboarding direct suite + Baseline |
| 8 | Cache posts schema capabilities / remove hot-path PRAGMA checks | Real cleanup with measurable low-risk benefit | Helper overhead stays in hot paths | Core DB + Posts / Privacy |
| 9 | Add small identity cache | Removes repeated identity reads across multiple screens | Repeated storage access remains noisy and slower | Identity / settings direct suite + Baseline |
| 10 | Low-risk cleanup pass (`cupertino_icons`, confirmed orphans only) | Safe cleanup after coverage is stronger | Accidental deletion of test-backed code | Baseline + affected subsystem gate |
| 11 | Add lightweight timing counters around send/retry/discovery/media | Useful after correctness work is protected | Performance discussions remain speculative | Direct area tests + selected gates |

---

## Session 1: Formalize Baseline + Subsystem Gates

**Goal:** Make future sessions consistent about what tests to run, and make sure existing high-value tests are not silently left out.

**Source Reports**
- `00-INDEX.md`
- `03-smoke-test-strategy.md`
- `14-regression-test-strategy.md`

**Code / Repo Entry Points to Inspect First**
- `Test-Flight-Improv/03-smoke-test-strategy.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- Existing test folders:
  - `test/features/feed/integration/`
  - `test/features/conversation/integration/`
  - `test/features/groups/integration/`
  - `test/features/posts/`
  - `integration_test/`
  - `test/core/services/`
  - `test/core/resilience/`
  - `test/core/lifecycle/`
  - `test/core/notifications/`
  - `test/features/contact_request/integration/`
  - `test/features/introduction/integration/`
  - `test/features/settings/integration/`
  - `test/features/share/integration/`
  - `test/integration/`
  - `test/features/identity/presentation/screens/`

**Inventory to Classify Before Freezing Gates**
- Start from the gate definitions already written in `14-regression-test-strategy.md`
- Treat those definitions as the draft
- Patch them during classification instead of rebuilding the gates from scratch
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `integration_test/background_reconnect_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/loading_states_smoke_test.dart`
- `test/features/loading_states_smoke_test.dart`
- `integration_test/posts_phase2_fake_test.dart`
- `integration_test/posts_phase3_fake_test.dart`
- `integration_test/posts_phase4_fake_test.dart`
- `integration_test/posts_phase5_fake_test.dart`
- `test/core/services/` (23 test files plus helper fake)
- `test/core/resilience/` (all 8 files)
- `test/core/lifecycle/` (all 15 files)
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/features/settings/integration/profile_picture_flow_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/integration/rapid_lock_unlock_integration_test.dart`
- `test/integration/relay_down_degradation_integration_test.dart`
- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/relay_chaos_soak_test.dart`
- `integration_test/soak_e2e_test.dart`
- `integration_test/bidi_text_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- `integration_test/identity_progress_performance_test.dart`

**Existing Tests to Reuse**
- `startup_router_recovery_test.dart`
- `qr_scanner_wired_test.dart`
- `offline_inbox_roundtrip_test.dart`
- `loading_states_smoke_test.dart`
- `posts_phase1_fake_test.dart`
- `group_messaging_smoke_test.dart`

**What To Produce**
- A gate-definition deliverable consisting of:
  - `scripts/run_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - the reference doc should list exact files per gate, nightly-only pool, optional/manual tests, out-of-gate tests with reasons, and known failures
- A bulk-classification policy stating that feature-local unit/widget tests remain implicitly covered by feature-level runs, while integration/cross-feature/core-service/orchestration tests must be explicitly classified
- A frozen checklist for:
  - Baseline Gate
  - 1:1 Reliability Gate
  - Feed / Surface Gate
  - Group Messaging Gate
  - Posts / Privacy Gate
  - Startup / Transport Gate
- Explicit classification for every high-value existing test reviewed in this session
- An explicit decision on:
  - the canonical `loading_states_smoke_test.dart` path
  - the current draft 1:1 gate size of 9 tests, including whether `quote_reply_thread_test.dart` stays in gate
- A completeness-check step that diffs all `*_test.dart` paths against the combined gate/reference lists
- Startup / Transport device handling documented as a raw command requirement or TODO, even if the script does not fully automate it yet

**Regression To Add First**
- None required if this stays documentation/script-only

**Direct Test Set**
- Validate each final gate definition by its explicit file list
- Run each finalized gate command once and record pass/fail per file so known failures are evidence-backed
- Run the completeness check after classification so unmatched test files are visible
- Document known failures instead of weakening the definition to make it look green

**Done When**
- Future sessions can say “run the 1:1 Reliability Gate” and mean the same exact file list every time
- No high-value existing test remains unclassified by accident
- Gate definitions use explicit file paths, not folder shorthands
- `Test-Flight-Improv/test-gate-definitions.md` exists as the reference source of truth
- The loading-state duplicate and 1:1 gate-count decision are resolved intentionally
- Startup / Transport documents the required raw device command even if script automation remains partial
- Known failing tests are documented separately instead of silently dropped
- No reviewer is still finding a new structural category of missing work

**Scope Guard**
- Do not redesign the test architecture
- Do not add a new large smoke matrix
- Do not change app code
- Do not add new tests in this session

---

## Session 2: Add Feed Inline Reply Durable-Send Regression

**Goal:** Add the missing test that proves feed-originated 1:1 send is as durable as conversation send.

**Source Reports**
- `08-network-1to1-messaging.md`
- `12-1to1-chat-use-case-audit.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`

**Existing Tests to Reuse**
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`

**Regression To Add First**
- A focused test proving:
  - feed inline reply enters the durable send path correctly
  - interruption / retry / recovery does not lose the message
  - behavior matches conversation-originated send expectations

**Likely File Areas to Edit**
- A new or expanded test in:
  - `test/features/feed/integration/`
  - or `test/features/conversation/integration/` if that is the better orchestration home

**Direct Test Set**
- New feed-inline-reply regression
- `flutter test test/features/feed/integration`
- `flutter test test/features/conversation/integration`

**Subsystem Gate**
- Feed / Surface Gate
- 1:1 Reliability Gate

**Baseline Gate**
- Yes

**Done When**
- There is a permanent regression test that fails if feed reply falls out of parity again

**Scope Guard**
- Do not fix behavior yet unless required to make the test deterministic
- The goal here is to define the missing contract first

---

## Session 3: Fix Durable Send-Path Parity Between Conversation and Feed Inline Reply

**Goal:** Make feed-originated 1:1 send use the same durable contract as the conversation path.

**Source Reports**
- `08-network-1to1-messaging.md`
- `12-1to1-chat-use-case-audit.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`

**Existing Tests to Reuse**
- Everything from Session 2
- Plus:
  - `test/features/conversation/integration/media_attachment_flow_test.dart`
  - `test/features/conversation/integration/media_retry_smoke_test.dart`
  - `test/features/conversation/integration/voice_message_exchange_test.dart`
  - `test/features/conversation/integration/incomplete_upload_recovery_test.dart`

**Regression That Must Already Exist**
- The feed inline reply durable-send regression from Session 2

**Direct Test Set**
- `flutter test test/features/feed`
- `flutter test test/features/conversation/integration`

**Subsystem Gate**
- Feed / Surface Gate
- 1:1 Reliability Gate

**Baseline Gate**
- Yes

**Startup / Transport Gate**
- Run if the fix touches bootstrap, inbox drain, or transport fallback behavior

**Done When**
- Feed and conversation entry points behave the same for durable send / retry / recovery
- The new regression stays green

**Scope Guard**
- Do not broaden into read receipts, typing indicators, or larger messaging product work
- Keep this strictly about send durability parity

---

## Session 4: Add Notification Adapter Boundary Tests

**Goal:** Strengthen the platform-facing notification layer that is lighter than the current domain/use-case coverage.

**Source Reports**
- `01-unit-test-coverage.md`
- `02-integration-test-coverage.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/local_notification_support.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`

**Existing Tests to Reuse**
- `test/core/notifications/notification_route_dispatch_test.dart`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_target_sender_id_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`

**Regression To Add First**
- Adapter-focused tests around:
  - notification payload translation
  - foreground display wiring
  - tap/open routing handoff
  - fallback behavior when exact platform support is unavailable

**Direct Test Set**
- `flutter test test/core/notifications`
- `flutter test test/features/push/application`

**Subsystem Gate**
- Baseline Gate is usually enough unless startup routing or deep-link bootstrap changed

**Baseline Gate**
- Yes

**Done When**
- Notification behavior is protected at the adapter boundary, not only inside pure use cases

**Scope Guard**
- Do not build a larger notification architecture
- Stay focused on correctness at the current plugin boundary

---

## Session 5: Add Post Presence Rejection Matrix

**Goal:** Cover the remaining nearby-post presence edge cases directly.

**Source Reports**
- `01-unit-test-coverage.md`
- `02-integration-test-coverage.md`
- `05-database-storage-performance.md` when schema-related assumptions matter

**Code Files to Inspect First**
- `lib/features/posts/application/handle_incoming_post_presence_use_case.dart`
- `lib/features/posts/application/post_presence_listener.dart`

**Existing Tests to Reuse**
- `test/features/posts/phase3/post_presence_listener_test.dart`
- `test/features/posts/phase3/posts_privacy_settings_repository_test.dart`

**Regression To Add First**
- Cases for:
  - blocked sender
  - stale snapshot
  - malformed timestamp
  - sender mismatch
  - any other explicit reject path found during code review

**Direct Test Set**
- `flutter test test/features/posts/phase3/post_presence_listener_test.dart`
- `flutter test test/features/posts`

**Subsystem Gate**
- Posts / Privacy Gate

**Baseline Gate**
- Yes

**Done When**
- The rejection matrix is directly covered and failures are easy to reason about

**Scope Guard**
- Do not expand into broad posts feature work
- Keep this about presence validation and privacy correctness

---

## Session 6: Add Announcement-Specific Happy-Path Regression

**Goal:** Make announcement coverage easier to understand in one focused test instead of spreading evidence across many files.

**Source Reports**
- `11-group-discussion-use-case-audit.md`
- `13-announcement-use-case-audit.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

**Existing Tests to Reuse**
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

**Regression To Add First**
- One concise create -> admin send -> reader receive/read-only -> member react flow

**Direct Test Set**
- New announcement-focused test
- `flutter test test/features/groups/application`
- `flutter test test/features/groups/presentation`

**Subsystem Gate**
- Group Messaging Gate

**Baseline Gate**
- Yes

**Done When**
- Announcement behavior is easy to verify from one focused regression, even though broader coverage still exists elsewhere

**Scope Guard**
- Do not drift into Go-side writer enforcement in this repo
- Do not add new announcement product features here

---

## Session 7: Add One Onboarding Golden Path

**Goal:** Add one confidence flow from identity creation through first meaningful user interaction.

**Source Reports**
- `02-integration-test-coverage.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/main.dart`
- identity startup / creation / recovery paths under `lib/features/identity/`
- contact-request flow under `lib/features/contact_request/`
- initial 1:1 messaging entry points under `lib/features/conversation/`

**Existing Tests to Reuse**
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`

**Regression To Add First**
- One happy-path integration test that proves:
  - identity is created or restored
  - contact request is accepted
  - first message succeeds

**Direct Test Set**
- New onboarding golden path
- `flutter test test/features/identity`
- `flutter test test/features/contact_request`
- `flutter test test/features/conversation`

**Subsystem Gate**
- Baseline Gate is usually enough
- Add 1:1 Reliability Gate if the new test reuses shared messaging code deeply

**Baseline Gate**
- Yes

**Done When**
- There is one concise top-to-bottom onboarding confidence flow

**Scope Guard**
- Only one golden path is needed
- Do not build a full onboarding matrix

---

## Session 8: Cache Posts Schema Capabilities / Remove Hot-Path PRAGMA Checks

**Goal:** Remove repeated runtime schema introspection from hot helper paths without changing behavior.

**Source Reports**
- `05-database-storage-performance.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/core/database/helpers/post_passes_db_helpers.dart`
- `lib/core/database/helpers/post_recipients_db_helpers.dart`
- related migrations under `lib/core/database/migrations/`

**Existing Tests to Reuse**
- `test/core/database/helpers/`
- `test/core/database/migrations/`
- `test/features/posts/`

**Regression To Add First**
- Helper-level tests proving both older and newer schema capability paths still behave correctly after caching

**Direct Test Set**
- `flutter test test/core/database/helpers`
- `flutter test test/core/database/migrations`
- `flutter test test/features/posts`

**Subsystem Gate**
- Posts / Privacy Gate

**Baseline Gate**
- Yes

**Done When**
- Hot-path PRAGMA checks are removed or minimized
- Behavior remains stable across supported schema states

**Scope Guard**
- Do not rewrite large query paths unless tests prove a real need
- Keep the change limited to schema capability detection/caching

---

## Session 9: Add Small Identity Cache

**Goal:** Remove repeated identity reads across screens while preserving correctness.

**Source Reports**
- `05-database-storage-performance.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/posts/presentation/screens/posts_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- identity wiring in `lib/main.dart`

**Existing Tests to Reuse**
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- settings/profile related tests under `test/features/settings/`

**Regression To Add First**
- Repository tests proving:
  - repeated `loadIdentity()` calls stay correct
  - cache invalidates or refreshes when identity changes
  - callers still get consistent values

**Direct Test Set**
- `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `flutter test test/features/settings`
- `flutter test test/features/feed`

**Subsystem Gate**
- Baseline Gate is usually enough

**Baseline Gate**
- Yes

**Done When**
- Repeated screen-driven identity loads are reduced without stale-data regressions

**Scope Guard**
- Do not redesign identity state management
- Keep the change inside a small repository-level cache

---

## Session 10: Low-Risk Cleanup Pass

**Goal:** Remove only the cleanup items that are already high-confidence and low-risk.

**Source Reports**
- `06-dead-code-lib.md`
- `07-dead-code-deps-config.md`
- `14-regression-test-strategy.md`

**Code Files to Inspect First**
- `pubspec.yaml`
- any specific orphan candidate named in `06-dead-code-lib.md`
- usage references from `rg`

**Existing Tests to Reuse**
- Baseline Gate
- Any subsystem gate for the area touched by a file deletion

**Regression To Add First**
- None by default
- Only add tests if cleanup unexpectedly crosses behavioral boundaries

**Direct Test Set**
- `flutter test`
- or smaller targeted suites plus Baseline Gate for incremental cleanup slices

**Subsystem Gate**
- Depends on what is removed
- If a candidate sits near feed, conversation, groups, posts, or startup, run that gate too

**Baseline Gate**
- Yes, after each cleanup slice

**Done When**
- `cupertino_icons` is removed safely
- Any deleted file has been confirmed unused by code, tests, and manual workflow requirements

**Scope Guard**
- Do not mass-delete files from the old dead-code report
- Confirm every deletion with search and tests first

---

## Session 11: Add Lightweight Timing Counters Around Send / Retry / Discovery / Media

**Goal:** Add just enough timing/operability evidence to support future decisions without building a full observability stack.

**Source Reports**
- `10-network-measurement-strategy.md`
- `08-network-1to1-messaging.md`
- `09-network-group-messaging.md`

**Code Files to Inspect First**
- 1:1 send/retry paths under `lib/features/conversation/application/`
- group send/retry paths under `lib/features/groups/application/`
- transport/bootstrap paths in `lib/main.dart` and related startup/resume code

**Existing Tests to Reuse**
- `test/features/conversation/integration/`
- `test/features/groups/integration/`
- startup / transport tests under `integration_test/`

**Regression To Add First**
- Only add targeted tests if metrics instrumentation changes behavior or error handling

**Direct Test Set**
- Area-specific direct suites

**Subsystem Gate**
- 1:1 Reliability Gate or Group Messaging Gate depending on where instrumentation lands

**Baseline Gate**
- Yes

**Startup / Transport Gate**
- Run if instrumentation touches transport/bootstrap/resume code

**Done When**
- There are lightweight local counters/timers for key send/retry/download/discovery events
- No exporter/dashboard architecture has been introduced

**Scope Guard**
- Do not build a full metrics collector/exporter stack yet
- Keep instrumentation local and removable

---

## Future Session Prompt Template

When starting a future planning session, use this structure:

```text
Open Test-Flight-Improv/15-session-todo-roadmap.md and plan Session <N>.
Read the listed source reports and code-entry files first.
Do not implement yet.
Tell me:
1. what the real scope is,
2. which files you need to inspect next,
3. what regression or tests must exist first,
4. what you would change,
5. which direct tests and gates you would run after implementation.
```

When starting a future execution session, use this structure:

```text
Execute Session <N> from Test-Flight-Improv/15-session-todo-roadmap.md.
Follow the scope guard.
Add the listed regression first if required.
Then implement the change and run the direct suite, subsystem gate, and baseline gate.
```

---

## Final Rules

- Do the safety-net work before cleanup or architecture cleanup
- Prefer targeted regressions over more generic smoke tests
- Use use-case and integration coverage first; device-backed tests only when the change actually reaches device/transport boundaries
- Keep each session scoped to one roadmap item unless two items are explicitly coupled
- If a session uncovers that a roadmap item is stale, update the roadmap before continuing

---

## Verdict

**This roadmap is the bridge between the reports and actual execution.** It tells a future session where to start reading, what contract to protect first, and what tests to run after each change. If followed consistently, it should let you improve the app incrementally without losing confidence or overengineering the test strategy.
