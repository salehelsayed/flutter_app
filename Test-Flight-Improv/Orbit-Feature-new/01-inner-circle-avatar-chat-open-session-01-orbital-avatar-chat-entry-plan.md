# Orbit Avatar Chat Entry Session Plan

Status: accepted

## Planning Progress

- `2026-05-25 12:59:13 CEST` - Planner started. Files inspected since last update: none beyond Evidence Collector corpus. Decision/blocker: evidence supports a narrow implementation-ready plan local to Orbit avatar widgets, `OrbitScreen` callback threading, and `OrbitWired` duplicate-open guard; no blocker. Next action: draft mandatory sections, exact regression contract, and stop rules.
- `2026-05-25 12:58:40 CEST` - Evidence Collector completed. Files inspected since last update: `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/14-regression-test-strategy.md`, `scripts/run_test_gates.sh`, `lib/features/orbit/presentation/widgets/orbital_avatar.dart`, `lib/features/orbit/presentation/widgets/orbital_visualization.dart`, `lib/features/orbit/presentation/widgets/overflow_badge.dart`, `lib/features/orbit/presentation/widgets/friend_row.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/orbit/domain/models/orbit_friend.dart`, `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`, `test/features/orbit/presentation/widgets/orbital_avatar_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`. Decision/blocker: evidence confirms a local Orbit presentation/wiring gap, with no direct device/relay requirement; no blocker to drafting. Next action: write the doc-scoped implementation-ready plan with regression-first tests and scope guard.
- `2026-05-25 12:56:23 CEST` - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-breakdown.md`, `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`, `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-01-orbital-avatar-chat-entry-plan.md`, `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`. Decision/blocker: session row and source problem are confirmed; no blocker to evidence collection. Next action: inspect only Orbit avatar/chat-entry production seams, direct tests, and named gate docs.
- `2026-05-25 12:55:30 CEST` - Controller intake started. Files inspected since last update: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-breakdown.md`, `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`, `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`. Decision/blocker: confirmed current session id `01-orbital-avatar-chat-entry`, intended plan path, and implementation-ready scope; no blocker. Next action: run the implementation-plan-orchestrator role sequence in one fresh child context and keep this artifact updated at role boundaries.

## Evidence Collector Findings

- The source doc says the current UX gap is that Orbit shows visual friend avatars in the "YOUR INNER CIRCLE" / close-friends area, but tapping them does not open chat; the required behavior applies to all visible inner and outer ring friend avatars while preserving row chat opening, center-avatar non-actionability, overflow non-actionability, blocked/archived boundaries, and unread freshness after return.
- The breakdown narrows this into one implementation-ready session: make visible orbital avatars call the same exact-friend Orbit 1:1 chat entry path used by friend rows, add shared duplicate-open protection, add accessible/actionable labels and comfortable hit targets, and prove row/visualization/navigation behavior stays intact.
- `OrbitalAvatar` is currently visual-only: it accepts `peerId`, `size`, `globalIndex`, `borderWidth`, and `borderColor`, then renders a `UserAvatar` inside a bordered circular container with a staggered scale/opacity animation.
- `OrbitalVisualization` currently receives `List<OrbitFriend> friends`, splits them into five inner-ring friends and eight outer-ring friends, and passes only `peerId`/visual styling into each `OrbitalAvatar`; it also renders the center `UserAvatar` and optional `OverflowBadge` without tap callbacks.
- `OrbitScreen` already receives `void Function(OrbitFriend) onFriendTap`; it passes active non-blocked header friends into `OrbitalVisualization`, while friend list rows call `onFriendTap(friend)` through `FriendRow`.
- `OrbitWired._onFriendTap` currently pushes `ConversationWired`, then marks the conversation read in the background and refreshes that friend after the pushed route returns. There is no visible duplicate-open guard in the current path.
- Existing direct tests cover rendering and row route behavior but not avatar actionability: `orbital_visualization_test.dart` covers heading, center avatar, ring counts, and overflow; `orbital_avatar_test.dart` covers visual avatar rendering; `orbit_wired_test.dart` covers row tap route push before read marking completes and the loading shell on pushed conversation route.
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` keep Orbit widget/wired tests outside frozen named gates by default. `baseline` and `1to1` are named gates, but this session only needs them if implementation touches shared navigation shell behavior or shared 1:1 messaging internals.

## Execution Contract

- Keep the change local to Orbit friend chat entry points.
- Do not change friend ranking, ring assignment, overflow behavior, the center
  user avatar, route architecture, conversation UI, message persistence,
  group/intro behavior, or archived/block/delete controls.
- Add actionable orbital avatar callbacks for visible inner and outer ring
  friends only.
- Reuse the existing Orbit friend `onFriendTap` route path so the opened
  conversation belongs to the exact tapped `OrbitFriend`.
- Add duplicate-open protection in the shared `OrbitWired._onFriendTap` path
  so both row taps and avatar taps are covered.
- Preserve read-marking and route-return friend refresh behavior.

## Implementation Summary

- `OrbitalAvatar` now accepts optional `onTap` and `semanticLabel` inputs.
  When actionable, it exposes a button semantic label and a 48 px opaque tap
  target while keeping the visual avatar size unchanged.
- `OrbitalVisualization` now threads each visible inner-ring and outer-ring
  `OrbitFriend` into an optional `onFriendTap` callback. The center user
  avatar and overflow badge remain non-chat-opening.
- `OrbitScreen` passes its existing `onFriendTap` callback into
  `OrbitalVisualization` for the already-rendered active, non-blocked header
  friends.
- `OrbitWired._onFriendTap` now guards route pushes per friend peer id while a
  push is pending, then releases the guard and refreshes the same friend after
  route return.
- A minimal prerequisite compile fix was applied in
  `lib/features/groups/presentation/widgets/group_name_panel.dart` by resolving
  the local `l10n` reference inside `_buildStartButton`; no wider group
  behavior was changed.

## Verification Evidence

- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "orbital avatar tap pushes exact conversation route and loading shell"` passed.
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --name "(rapid repeated orbital avatar taps|avatar-opened unread friend|blocked and archived contacts|friend tap pushes one conversation route)"` passed.
- After the separate localization session completed, the full focused Orbit
  evidence command passed:
  `flutter test --no-pub test/features/orbit/presentation/widgets/orbital_avatar_test.dart test/features/orbit/presentation/widgets/orbital_visualization_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`.
- `git diff --check` passed.

## Session Closure Verdict

- Verdict: `accepted`
- Accepted scope: the repo-owned Orbit avatar chat-entry implementation and
  targeted OrbitWired behavior are landed.
- Residual repo-owned Orbit blockers: none found.
