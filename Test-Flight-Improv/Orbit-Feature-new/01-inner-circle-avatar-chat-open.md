# Inner Circle Friend Avatars Open Chat

## 1. Title and Type

- Title: Inner Circle friend avatars open the main chat window
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`

## 2. Problem Statement

- Users want to open a friend's 1:1 chat directly from the Orbit "Inner Circle" visual area.
- Today, Orbit presents friend avatars around the user's avatar, but tapping those avatars does not open the chat.
- This creates a confusing dead end: the visual treatment suggests close friends are directly actionable, while users must instead use the existing friend list row entry point.

## 3. Impact Analysis

- Affected users: users who rely on Orbit's top visual area to reach close or recently active friends.
- When it appears: whenever Orbit has visible friend avatars in the "YOUR INNER CIRCLE" / "Close Friends" section.
- Severity: moderate UX friction. The underlying chat route exists and list-row tapping works, but the more prominent visual friend entry point is non-actionable.
- Frequency: likely recurring for users who start from the visual inner-circle area rather than the scrollable friend list.
- Confusion cost: users may assume the avatar tap failed, the app is unresponsive, or the visual area is decorative despite representing real friends.

## 4. Current State

- Orbit loads active contacts and conversation summaries into `OrbitFriend` models, then sorts friends by latest message timestamp. Evidence: `lib/features/orbit/application/load_orbit_data_use_case.dart:12`, `lib/features/orbit/application/load_orbit_data_use_case.dart:100`, and `lib/features/orbit/application/load_orbit_data_use_case.dart:159`.
- The Orbit header renders `OrbitalVisualization` with active non-blocked friends only. Evidence: `lib/features/orbit/presentation/screens/orbit_screen.dart:374` and `lib/features/orbit/presentation/screens/orbit_screen.dart:377`.
- `OrbitalVisualization` displays the first 5 friends on the inner ring, the next 8 on the outer ring, and an overflow badge for additional friends. Evidence: `lib/features/orbit/presentation/widgets/orbital_visualization.dart:40`, `lib/features/orbit/presentation/widgets/orbital_visualization.dart:84`, and `lib/features/orbit/presentation/widgets/orbital_visualization.dart:105`.
- The visual section currently includes the hardcoded heading `YOUR INNER CIRCLE` and the localized `orbit_close_friends` label below it. Evidence: `lib/features/orbit/presentation/widgets/orbital_visualization.dart:50`, `lib/features/orbit/presentation/screens/orbit_screen.dart:383`, and `lib/l10n/app_en.arb:142`.
- `OrbitalAvatar` renders a friend avatar with animation and border styling, but the widget's current public inputs are visual only: `peerId`, `size`, `globalIndex`, `borderWidth`, and `borderColor`. Evidence: `lib/features/orbit/presentation/widgets/orbital_avatar.dart:7`.
- Orbit already has a main friend-tap flow for opening a 1:1 conversation from list rows. `OrbitScreen` receives `onFriendTap`; `FriendRow` calls it on tap; `OrbitWired._onFriendTap` pushes `ConversationWired`, then marks the conversation read in the background and refreshes the friend after return. Evidence: `lib/features/orbit/presentation/screens/orbit_screen.dart:185`, `lib/features/orbit/presentation/screens/orbit_screen.dart:963`, and `lib/features/orbit/presentation/screens/orbit_wired.dart:1516`.
- Existing tests partially cover the adjacent behavior:
  - `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` covers rendering of the inner-circle heading, center avatar, ring avatars, ring counts, and overflow badge.
  - `test/features/orbit/presentation/widgets/orbital_avatar_test.dart` covers visual rendering of `OrbitalAvatar`.
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart` covers that tapping a friend list row pushes the conversation route before read marking completes, and that the pushed route shows the conversation loading shell.
- Current test gap: no existing test was found for tapping an avatar in the orbital visualization and reaching the same user-visible chat destination as tapping the friend list row.

## 5. Scope Clarification

- In scope:
  - visible friend avatars in the Orbit "Inner Circle" / close-friends visual area are actionable as chat entry points
  - tapping a visible friend avatar opens that friend's main 1:1 chat window
  - the avatar entry point preserves the same user-visible chat-opening expectations as the existing friend list row
  - the behavior applies to visible friend avatars on both the inner and outer visible rings
  - accessibility-facing behavior should communicate that a visible friend avatar can open chat
- Non-goals:
  - changing how friends are ranked, sorted, or assigned to rings
  - changing the "Inner Circle" or "Close Friends" copy
  - changing the main conversation route, chat UI, read/unread policy, or message repository behavior
  - changing group rows, intro rows, QR actions, search, archive/block/delete actions, or overflow badge behavior
  - making the user's own center avatar open any destination
  - adding profile previews, long-press menus, or alternate friend actions from the orbital area
- Accepted ambiguities for the later implementation pass:
  - the exact tap affordance, pressed state, and motion treatment are not specified here
  - whether product language treats only the first ring as "inner circle" or the full visible orbital friend set as the actionable close-friends area remains open; this spec covers all visible friend avatars under that visual section
  - how much accessibility label detail is appropriate can be decided during implementation, as long as the user-visible intent is clear

## 6. Test Cases

### Happy Path

- `TC-OFN-01-H01` Given Orbit shows a friend avatar on the inner visible ring, when the user taps that avatar, then the main 1:1 chat window for that friend opens.
- `TC-OFN-01-H02` Given Orbit shows a friend avatar on the outer visible ring, when the user taps that avatar, then the main 1:1 chat window for that friend opens.
- `TC-OFN-01-H03` Given a friend has unread messages in Orbit, when the user opens that friend's chat from the orbital avatar, then the user reaches the same chat surface they would reach from the friend list row.
- `TC-OFN-01-H04` Given the user opens a chat from an orbital avatar, when the chat route is loading its initial content, then the user sees the same conversation loading state expected for the existing Orbit friend-row entry point.
- `TC-OFN-01-H05` Given a visible orbital friend avatar is available to assistive technologies, when the user navigates to it through accessibility controls, then it is announced as an actionable chat entry for that friend.

### Edge Cases

- `TC-OFN-01-E01` Given Orbit has no friends in the orbital visualization, when the user taps around the empty visual area or the center user avatar, then no arbitrary friend chat opens.
- `TC-OFN-01-E02` Given a blocked friend is excluded from the orbital visualization, when Orbit renders the inner-circle area, then that blocked friend cannot be opened from the visual avatar area.
- `TC-OFN-01-E03` Given a friend is archived and not part of the active Orbit header friend set, when the user views Orbit including the archived tab, then that archived friend does not appear or open from the orbital visualization.
- `TC-OFN-01-E04` Given Orbit has more friends than the visible avatar limit and shows an overflow badge, when the user taps the overflow badge, then no arbitrary 1:1 chat opens for a hidden friend.
- `TC-OFN-01-E05` Given the user rapidly taps the same visible orbital avatar more than once while the chat opening transition is pending, then the app opens one chat destination for that friend rather than stacking duplicate chat windows.
- `TC-OFN-01-E06` Given the user returns from the opened chat to Orbit, then the Orbit screen remains usable and the same friend can still be reached from the list row.

### Regressions to Preserve

- `TC-OFN-01-R01` Preservation/regression: Given the user taps a friend in the Orbit list row, then the main 1:1 chat window still opens as it does today.
- `TC-OFN-01-R02` Preservation/regression: Given Orbit renders the orbital visualization, then the existing center avatar, ring avatar counts, ring placement expectations, and overflow badge behavior remain intact.
- `TC-OFN-01-R03` Preservation/regression: Given a friend is blocked, archived, or deleted through existing Orbit controls, then the orbital visualization and list continue to reflect that friend state consistently.
- `TC-OFN-01-R04` Preservation/regression: Given Feed and Orbit navigation are available, opening chat from the inner-circle area does not break returning to Orbit or navigating back to Feed.
- `TC-OFN-01-R05` Preservation/regression: Given the user opens and returns from chat through an orbital avatar, then the Orbit screen still allows normal friend list navigation and at least one lightweight adjacent Orbit control check, such as search or Feed/Orbit navigation, to continue working.

### Acceptance Evidence Notes

- Focused user-interface acceptance evidence is needed for avatar tap behavior because the current coverage confirms rendering but not actionability.
- Integration evidence is needed for the full user-visible outcome from Orbit avatar tap to the main 1:1 chat window, including the same loading and route behavior already expected from list-row tapping.
- Lightweight smoke evidence is useful after the change because Orbit contains adjacent controls in the same screen; this spec does not require an exhaustive sweep of every unrelated Orbit control.
