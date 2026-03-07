# PERF-02 TDD Orchestration

## Goal

Implement `PERF-02 Add Loading Skeletons and Navigate-First Hydration` from
`UI-UX-Perf-Improvements/impl-backlog.md` with a test-first workflow and up to
3 coding agents.

This plan is execution-oriented. It assumes the agents are working in separate
worktrees or branches and will merge back into one integration branch.

---

## Source Of Truth

- Backlog item: `UI-UX-Perf-Improvements/impl-backlog.md`
- Supporting rationale: `UI-UX-Perf-Improvements/Top-Findings.md`
- Existing execution log: `UI-UX-Perf-Improvements/execution-log.md`

Backlog acceptance for `PERF-02`:
- No blank Feed state during initial load.
- Opening a conversation shows shell UI immediately.
- Perceived route speed improves even when data load time stays the same.

---

## Current Repo State

`PERF-02` is partially implemented already.

Implemented and already covered:
- Feed loading cards in `lib/features/feed/presentation/screens/feed_screen.dart`
- Feed loading tests in
  `test/features/feed/presentation/screens/feed_screen_test.dart`
- Conversation loading shell in
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Conversation loading tests in
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  and
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Feed navigate-first behavior in
  `test/features/feed/presentation/screens/feed_wired_test.dart`

Remaining gaps:
- Orbit has no dedicated initial-loading placeholder path.
- Orbit still blocks route push on `markConversationRead()` in
  `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- Orbit hydration is not split into "active content now, archived content later"
  from the perspective of visible loading UX.

This orchestration is therefore centered on Orbit and on preserving the
conversation-shell contract.

---

## Scope

In scope:
- Orbit initial loading placeholders.
- Orbit tab-aware placeholder behavior during background hydration.
- Orbit friend tap should push the conversation route immediately.
- Conversation shell must remain visible immediately after route push while data
  hydrates.
- Regression coverage for already-implemented Feed and Conversation behavior.

Out of scope:
- Feed visual redesign.
- Group conversation loading-shell redesign.
- Blur, animation-density, sliver, or incremental-update work outside `PERF-02`.

---

## Agent Topology

Use 3 agents maximum.

Parallel start:
- Agent 1: Orbit pure-UI loading placeholders
- Agent 2: Orbit navigate-first conversation entry

Sequenced after both:
- Agent 3: Orbit wired hydration sequencing and final integration

Why this split:
- Agent 1 mostly owns `OrbitScreen` and pure UI tests.
- Agent 2 mostly owns `OrbitWired` tap flow plus conversation-entry regression.
- Agent 3 integrates the new loading contract into the wired layer and resolves
  any overlap between UI placeholders and data hydration timing.

---

## Shared Rules

All agents must follow these rules:

1. Start with RED tests. Do not write production code first.
2. Do not weaken or delete existing Feed / Conversation `PERF-02` coverage.
3. Do not make placeholder widgets shimmer or animate continuously.
4. Do not allow placeholders to replace already-hydrated visible content.
5. Do not `await` read-marking, preload, or other async work before pushing the
   conversation route from Orbit.
6. Preserve the current visual language: dark ambient background, glass cards,
   stable header/search/FAB chrome.

---

## Existing Tests To Preserve

These tests are already the contract for the implemented portion of `PERF-02`.
They must keep passing throughout the lane work:

`test/features/feed/presentation/screens/feed_screen_test.dart`
- `renders loading placeholders while feed is still loading`
- `swaps loading placeholders for real feed items when data arrives`

`test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `shows loading shell while initial conversation page is still loading`

`test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `shows loading shell until the initial page resolves`

`test/features/feed/presentation/screens/feed_wired_test.dart`
- `send message pushes conversation route before read marking completes`
- `view earlier pushes conversation route before conversation preload resolves`

---

## File Inventory

Primary implementation files:
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`

Primary test files:
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  (new)
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

Helpful existing reference tests:
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

---

## Agent 1

### Lane

`perf02/a-orbit-shell`

### Goal

Add pure-UI Orbit loading placeholders and lock the placeholder contract with
isolated widget tests.

### Ownership

Primary files:
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

Secondary references:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

### RED Tests To Add First

Create `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
with these exact test names:

- `renders loading placeholders while all tab is still hydrating`
- `renders archived loading placeholders when archived tab is selected and archived data is not ready`
- `does not render placeholders after real orbit items are available`
- `keeps orbit chrome visible while loading placeholders are shown`

Expected assertions:
- Placeholder keys exist, for example:
  - `orbit-loading-row-0`
  - `orbit-loading-row-1`
  - `orbit-loading-row-2`
- `Friends`, close button, search trigger, and FAB still render.
- No empty archived state while archived data is still loading.
- No placeholder rows once `mergedItems` is non-empty.

### GREEN Implementation Target

Implement the smallest change set necessary in `orbit_screen.dart`:

- Extend `OrbitViewProjection` with tab-aware loading state, for example:
  - `bool isInitialLoading`
  - or separate readiness booleans if needed by Agent 3 later
- Add a pure-UI loading sliver / adapter for Orbit rows.
- Keep placeholder visuals static and cheap:
  - translucent row card
  - avatar stub
  - 2-3 text bars
- Render placeholders only when the currently selected tab has no hydrated
  content yet.
- Keep current header, close button, search trigger, search dock, and FAB
  behavior unchanged.

### REFACTOR Constraints

- Reuse existing Orbit screen test helpers where practical.
- Avoid introducing a placeholder widget tree that requires real repositories.
- Keep placeholder count fixed and deterministic.

### Lane Verification

Run:

```bash
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
```

### Handoff Contract

Before handoff, Agent 1 must provide:
- the final placeholder API expected by `OrbitScreen`
- the exact key names added for loading rows
- any new projection fields Agent 3 must populate

### Prompt For Agent 1

```text
Implement the pure-UI portion of PERF-02 for Orbit.

Constraints:
- Start with failing widget tests only.
- Work only in Orbit screen / pure UI territory unless a test setup helper must move.
- Preserve current Orbit chrome and visual language.
- Placeholders must be static, not shimmer-based.
- Do not let placeholders replace real rows once data exists.

Add this new test file first:
- test/features/orbit/presentation/screens/orbit_screen_loading_test.dart

Use these exact test names:
- renders loading placeholders while all tab is still hydrating
- renders archived loading placeholders when archived tab is selected and archived data is not ready
- does not render placeholders after real orbit items are available
- keeps orbit chrome visible while loading placeholders are shown

Then implement the minimum production code in:
- lib/features/orbit/presentation/screens/orbit_screen.dart

Deliverables:
- new loading test file
- updated OrbitScreen / OrbitViewProjection contract
- note to integration lane describing the projection fields required from OrbitWired
```

---

## Agent 2

### Lane

`perf02/b-nav-first`

### Goal

Make Orbit conversation entry navigate first and preserve the immediate
conversation shell contract with tests.

### Ownership

Primary files:
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

Secondary files:
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`

Reference parity:
- `test/features/feed/presentation/screens/feed_wired_test.dart`

### RED Tests To Add First

Add these exact test names to
`test/features/orbit/presentation/screens/orbit_wired_test.dart`:

- `friend tap pushes conversation route before read marking completes`
- `pushed conversation route shows loading shell before delayed initial page resolves`

Recommended harness pattern:
- create a delayed / gated message repository in the Orbit test file or a local
  helper mirroring the existing Feed test pattern
- use `NavigatorObserver` to detect route push timing
- gate `markConversationAsRead()` separately from initial message-page loading

Assertions:
- route push count increments immediately after tap
- push occurs before the read-marking gate is released
- the pushed route contains `conversation-loading-shell`
- header and composer are visible on first route frame

### GREEN Implementation Target

Change `OrbitWired._onFriendTap()` so it:
- pushes the conversation route immediately
- does not await `markConversationRead()` before navigation
- keeps the existing post-pop refresh path

Acceptable implementations:
- fire-and-forget `markConversationRead(...)` before or after push
- or rely on `ConversationWired._markAsRead()` only

Preferred implementation:
- let `ConversationWired` remain the canonical mark-read path and remove the
  navigation-blocking await from Orbit

### REFACTOR Constraints

- Do not regress Feed parity.
- Do not add duplicate mark-read writes if they are not needed.
- Keep route transition type unchanged.

### Lane Verification

Run:

```bash
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
```

### Handoff Contract

Before handoff, Agent 2 must provide:
- whether Orbit still issues any explicit pre-push mark-read call
- whether any test helper was added that Agent 3 should reuse

### Prompt For Agent 2

```text
Implement the navigate-first half of PERF-02 for Orbit.

Constraints:
- Start with RED tests in orbit_wired_test.dart.
- Make Orbit behave like Feed with respect to route push timing.
- The conversation route must show shell UI immediately while initial page data is still delayed.
- Do not change Feed logic except to keep its existing tests green.

Add these exact tests first:
- friend tap pushes conversation route before read marking completes
- pushed conversation route shows loading shell before delayed initial page resolves

Primary file to change:
- lib/features/orbit/presentation/screens/orbit_wired.dart

Reference behavior:
- test/features/feed/presentation/screens/feed_wired_test.dart

Deliverables:
- updated Orbit navigation flow
- route-timing tests
- note on whether explicit pre-push mark-read is still present
```

---

## Agent 3

### Lane

`perf02/c-orbit-hydration`

### Goal

Wire the new Orbit loading contract into real Orbit hydration so active content
can appear quickly while archived content hydrates in the background.

### Start Condition

Start after Agent 1 and Agent 2 have landed or after rebasing on both lane
heads.

### Ownership

Primary files:
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

Secondary references:
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

### RED Tests To Add First

Add these exact test names to
`test/features/orbit/presentation/screens/orbit_wired_test.dart`:

- `all tab renders active friends before archived hydration completes`
- `all tab renders active groups before archived hydration completes`
- `archived tab shows loading placeholders before archived data resolves`
- `archived tab swaps placeholders for archived rows when archived hydration completes`
- `background archived hydration does not replace visible all-tab rows with placeholders`

Recommended harness pattern:
- use delayed contact / message / group repository helpers
- gate archived contacts and archived groups independently
- publish active data immediately and hold archived data behind a completer

Assertions:
- active rows become visible without waiting for archived gates
- archived tab shows placeholders instead of blank space or archived empty state
- archived rows replace placeholders once gate completes
- visible all-tab content remains on-screen throughout background hydration

### GREEN Implementation Target

Refactor `OrbitWired` to publish more incrementally:

- Track readiness separately for:
  - active friends
  - archived friends
  - active groups
  - archived groups
- Publish active projections as soon as active data returns.
- Hydrate archived content in the background.
- Populate the loading fields expected by `OrbitScreen`.
- Ensure tab-aware behavior:
  - `all` tab should show active content as soon as it exists
  - `archived` tab should show placeholders until archived data exists
  - hydrated content must win over placeholders

Suggested state shape:

```text
_activeFriendsLoaded
_archivedFriendsLoaded
_activeGroupsLoaded
_archivedGroupsLoaded
```

Or equivalent derived projection flags if cleaner.

### REFACTOR Constraints

- Keep existing incremental refresh behavior for incoming events.
- Do not reintroduce full Orbit reloads on every event.
- Do not break intros tab or archived-groups behavior.

### Lane Verification

Run:

```bash
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
```

### Handoff Contract

Before handoff, Agent 3 must provide:
- final Orbit loading-state model
- any added delayed fake helpers
- confirmation that placeholders never override hydrated rows

### Prompt For Agent 3

```text
Implement the wired hydration sequencing for PERF-02 in Orbit after rebasing on the shell and navigate-first lanes.

Constraints:
- Start with failing tests in orbit_wired_test.dart.
- Publish active Orbit content as soon as it is ready.
- Archived data must hydrate in the background.
- Archived tab must show placeholders while archived data is pending, not blank space.
- Do not let background hydration replace visible all-tab content with placeholders.
- Preserve existing incremental update behavior and existing archived/intros coverage.

Add these exact tests first:
- all tab renders active friends before archived hydration completes
- all tab renders active groups before archived hydration completes
- archived tab shows loading placeholders before archived data resolves
- archived tab swaps placeholders for archived rows when archived hydration completes
- background archived hydration does not replace visible all-tab rows with placeholders

Primary file to change:
- lib/features/orbit/presentation/screens/orbit_wired.dart

Deliverables:
- incremental Orbit loading-state wiring
- hydration tests
- final note on the loading-state API shared with OrbitScreen
```

---

## Merge Order

Recommended merge sequence:

1. Merge Agent 1 into the integration branch.
2. Merge Agent 2 into the integration branch.
3. Rebase Agent 3 on top of the integrated result.
4. Resolve any overlap in `orbit_wired.dart`.
5. Run the full verification matrix.

If Agent 1 introduces projection fields that Agent 3 later changes, Agent 3 is
the final owner of the projection contract.

---

## Full Verification Matrix

### Targeted Tests

```bash
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart
```

### Analyze

```bash
flutter analyze lib/features/orbit/presentation/screens lib/features/conversation/presentation/screens test/features/orbit/presentation/screens test/features/conversation/presentation/screens
```

### Manual PERF-00 QA

Use the same device class before and after.

Flows to verify:
- Launch app into Feed:
  - Feed shows placeholders or content immediately, never a blank body.
- Feed -> Orbit:
  - Orbit shell appears immediately.
  - `All` tab shows either placeholders or active rows immediately.
- Orbit -> Archived:
  - Archived shows placeholders while archived data is pending.
  - Archived rows replace placeholders without flicker.
- Orbit -> friend tap -> conversation:
  - route pushes immediately
  - conversation header and composer land immediately
  - loading shell is visible until message page resolves
- Return from conversation:
  - Orbit row state remains consistent
  - unread/read state is sensible

---

## Definition Of Done

`PERF-02` is done only when all of the following are true:

- Feed loading-placeholder tests still pass.
- Conversation loading-shell tests still pass.
- Orbit has dedicated placeholder coverage for initial and archived hydration.
- Orbit friend tap no longer blocks route push on read-marking.
- Conversation shell is visible immediately after Orbit navigation.
- Archived hydration is backgrounded and tab-aware.
- No placeholder path overwrites already-hydrated visible rows.
- Manual route-entry QA shows no blank frame on Feed -> Orbit -> Conversation.

---

## Final Notes For The Integrator

- Prefer extending existing fake repositories in the test files instead of
  creating a new fake framework.
- Keep new placeholder keys explicit and deterministic for test readability.
- If the implementation naturally needs one more small helper widget, keep it
  private to `orbit_screen.dart` unless reuse is proven.
- If a design tradeoff appears, bias toward stable shell rendering over visual
  flair. `PERF-02` is a perceived-speed task, not a redesign task.
