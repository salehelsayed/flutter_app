# Inner Circle Avatar Chat Open Session Breakdown

## Decomposition artifact

- Artifact path: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`
- Decomposition date: `2026-05-25`
- Intended plan file pattern: `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-<session-id>-plan.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later execution must be refreshed against landed code, current tests, and current gate definitions before closure.

## recommended plan count

Recommended plan count: `1`

The smallest safe split is one Orbit friend chat-entry session. The missing
behavior is one cohesive UI/wiring seam: visible orbital friend avatars need to
call the same exact-friend 1:1 chat opening path used by Orbit friend rows,
while that shared path gains duplicate-open protection, accessibility labels,
comfortable hit targets, and stale-unread refresh proof. Splitting avatar
tap, duplicate guard, and unread refresh would create misleading partial states
because the avatar path is only correct when it reaches the same guarded
friend-specific route and refresh behavior as the existing row path.

## overall closure bar

Doc `01-inner-circle-avatar-chat-open.md` is complete when:

- visible inner-ring and outer-ring orbital friend avatars are actionable
  chat entry points
- tapping an orbital avatar opens the main 1:1 chat for the exact tapped
  friend, not another friend or a generic conversation
- the orbital avatar path and existing Orbit friend-row path share
  duplicate-open protection for rapid repeated taps while a route open is
  pending
- each visible orbital friend avatar exposes an actionable accessibility label
  such as `Open chat with Bob`
- small visual avatars have a comfortable mobile hit target without changing
  the center user avatar or overflow badge into chat entry points
- opening an unread friend from an orbital avatar and returning to Orbit does
  not leave stale unread state
- existing Orbit friend row chat opening, orbital visualization rendering,
  overflow badge behavior, blocked/archived boundaries, and lightweight Orbit
  navigation/search behavior keep working
- the solution stays local to Orbit friend chat entry points and does not
  redesign Orbit ranking, routing, conversation UI, archived/group/intro
  behavior, or unrelated controls

## source of truth

Primary governing docs:

- `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts governing the split:

- `lib/features/orbit/presentation/widgets/orbital_visualization.dart` renders
  the first five friends on the inner ring, the next eight on the outer ring,
  and an overflow badge for hidden friends.
- `lib/features/orbit/presentation/widgets/orbital_avatar.dart` is currently
  visual-only and accepts only `peerId`, size, animation index, and border
  styling inputs.
- `lib/features/orbit/presentation/screens/orbit_screen.dart` currently passes
  non-blocked header friends into `OrbitalVisualization` and separately uses
  `FriendRow(onTap: () => onFriendTap(friend))` for row-based chat opening.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` currently pushes
  `ConversationWired` from `_onFriendTap`, then marks the conversation read in
  the background and refreshes that friend after route return.
- `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
  already covers rendering, ring counts, and overflow rendering but not avatar
  actionability.
- `test/features/orbit/presentation/widgets/orbital_avatar_test.dart` already
  covers visual avatar rendering but not semantics or tap behavior.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  covers existing row-based conversation opening and loading-shell behavior,
  so the avatar path should reuse or extend this Orbit-owned route proof
  instead of inventing a new conversation route contract.
- `test-gate-definitions.md` keeps Orbit wiring tests outside frozen named
  gates unless a named gate's owned area changes; direct Orbit widget/wired
  tests are the relevant focused evidence for this doc.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and
  `scripts/run_test_gates.sh` decide named gate membership
- the source doc remains the product intent source unless current repo
  evidence proves a requirement stale or outside scope

## run mode snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal, matrix, or closure doc path:
  `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`
- Source row/status vocabulary:
  source doc test cases `TC-OFN-01-*`; no row-status matrix vocabulary is
  defined for this doc
- Overall closure bar:
  all visible orbital friend avatar chat-entry requirements in
  `## overall closure bar` are implemented and backed by focused Orbit tests
  or exact blocker evidence
- Final verdict policy for this run:
  allowed final program verdicts are `closed`,
  `accepted_with_explicit_follow_up`, `residual_only`, and `still_open`;
  `closed` requires the session ledger and source doc acceptance evidence to
  show the full Orbit avatar chat-entry contract is satisfied

## session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-orbital-avatar-chat-entry` | Orbital avatars reuse exact-friend guarded chat opening | `implementation-ready` | `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-01-orbital-avatar-chat-entry-plan.md` | none | `accepted` |

## ordered session breakdown

### Session 01: Orbital avatars reuse exact-friend guarded chat opening

- Session id: `01-orbital-avatar-chat-entry`
- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-01-orbital-avatar-chat-entry-plan.md`
- Exact scope:
  - extend `OrbitalVisualization` so each visible inner-ring and outer-ring
    friend avatar receives its `OrbitFriend` and a friend-specific chat-open
    callback
  - keep the center user avatar and overflow badge non-chat-opening
  - make `OrbitalAvatar` optionally actionable with a comfortable hit target,
    touch feedback that does not disturb ring placement, and a
    friend-specific accessibility label such as `Open chat with Bob`
  - thread the existing Orbit friend tap callback from `OrbitScreen` into the
    orbital visualization for the active, non-blocked header friends already
    rendered there
  - add shared duplicate-open protection to the Orbit 1:1 friend chat entry
    path so rapid repeated taps from either an orbital avatar or a friend row
    do not stack duplicate conversations while the first push is pending
  - preserve the existing route behavior that pushes `ConversationWired`,
    shows the conversation loading shell, marks the conversation read in the
    background, and refreshes the tapped friend after returning
  - add focused widget/wired regressions for inner-ring avatar tap, outer-ring
    avatar tap, exact tapped friend selection, duplicate-open protection for
    avatar and row entry points, semantics/actionable label, hit target, unread
    refresh after return, overflow/center non-actionability, blocked/archived
    boundaries, and lightweight Orbit navigation/search preservation where
    the current test harness can prove them without a broad redesign sweep
- Why it is its own session:
  - this is one user-visible Orbit friend chat-entry seam with one shared
    correctness contract
  - duplicate protection is inseparable from adding a second entry point to the
    same route
  - unread freshness is already owned by the existing row tap path and should
    be proven through the same callback rather than through a separate
    repository or route session
  - the session can land and be verified independently without persistence,
    transport, database, route redesign, ranking, group, intro, or archived
    control changes
- Likely code-entry files:
  - `lib/features/orbit/presentation/widgets/orbital_visualization.dart`
  - `lib/features/orbit/presentation/widgets/orbital_avatar.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
  - `flutter test test/features/orbit/presentation/widgets/orbital_avatar_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - targeted assertions that tapping an inner-ring avatar and an outer-ring
    avatar invokes the tapped friend's exact peer/contact
  - targeted duplicate-open assertions for rapid repeated avatar taps and
    rapid repeated row taps
  - targeted semantics assertions for `Open chat with <friend name>`
  - targeted stale-unread refresh assertion after returning from a chat opened
    through the avatar path
  - targeted preservation assertions for overflow badge rendering/non-opening,
    center user avatar non-opening, blocked friend exclusion, archived friend
    boundary, and lightweight Orbit search or Feed/Orbit navigation behavior
- Likely named gates:
  - none by default; this is Orbit feature-local presentation/wiring work
  - run `./scripts/run_test_gates.sh baseline` if the route-opening change
    touches shared navigation shell behavior or if focused Orbit evidence is
    insufficient
  - run `./scripts/run_test_gates.sh 1to1` only if the implementation changes
    shared 1:1 send, retry, inbox, listener, or conversation persistence
    behavior; the intended scope should not require that
  - run `./scripts/run_test_gates.sh completeness-check` only if gate
    definitions, integration tests, or test-classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and final program verdict
  - `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open.md`
    with concise acceptance evidence and any exact external blocker if one is
    discovered
  - no new matrix doc is needed for this narrow Orbit feature unless execution
    adds or reclassifies a durable integration/gate test
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## why this is not fewer sessions

Zero sessions would leave the visual Inner Circle avatars non-actionable and
would not satisfy the source doc.

## why this is not more sessions

Separate sessions for avatar actionability, duplicate-open protection,
accessibility, and unread refresh would not create independently safe product
states. The avatar path is correct only if it opens the exact tapped friend
through the guarded existing chat path and returns to Orbit with fresh unread
truth. The relevant production files and focused tests are all Orbit-owned
presentation/wiring surfaces, so one implementation-ready session is the
smallest meaningful split.

## reviewer pass

- Sufficiency: `1` session is sufficient.
- Merge candidates: none.
- Required splits: none.
- Missing tests or named gates: execution must add focused avatar-action,
  duplicate-open, semantics, and stale-unread regressions; no frozen named gate
  needs to widen at decomposition time.
- Meaningful verified state: yes. The single session can land the full visible
  avatar chat-entry behavior and preserve row/visualization/navigation
  regressions without waiting on other work.
- Matrix responsibility: clear. Reuse this doc-scoped breakdown and source
  doc; do not invent a new matrix for this narrow Orbit feature.

## arbiter outcome

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences:
  - the center user avatar and overflow badge remain non-chat-opening
  - blocked and archived boundaries are preserved rather than redesigned
  - product copy for the section heading is unchanged
  - no route, ranking, conversation UI, transport, persistence, group, intro,
    archive, block, delete, or full adjacent-control redesign is added

## downstream execution path

1. Reuse or create the doc-scoped plan
   `Test-Flight-Improv/Orbit-Feature-new/01-inner-circle-avatar-chat-open-session-01-orbital-avatar-chat-entry-plan.md`.
2. Execute that plan through `$implementation-execution-qa-orchestrator`.
3. Close the session with `$implementation-closure-audit-orchestrator`.
4. After the session resolves, run one final whole-doc acceptance/closure pass
   and persist a final program verdict in this breakdown artifact.

Allowed final program verdicts for this rollout are `closed`,
`accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`.
`still_open` is only acceptable as an honest unfinished/blocker state, not a
completion verdict.

## controller progress

- `2026-05-25` - Local decomposition fallback created this reusable adjacent
  breakdown after the spawned decomposition attempt left no current-doc
  breakdown artifact.
- `2026-05-25` - Spawned pipeline-controller attempt produced the doc-scoped
  session plan but did not reach execution or a final verdict within bounded
  waits. Local pipeline fallback resumed from the landed artifacts.
- `2026-05-25` - Session `01-orbital-avatar-chat-entry` implementation landed
  in Orbit-owned avatar, visualization, screen, and wired route-entry files,
  with focused Orbit widget/wired tests added. A minimal prerequisite compile
  fix landed in `group_name_panel.dart` for a dirty-workspace local `l10n`
  reference before the user clarified that a separate localization session was
  in progress.
- `2026-05-25` - After the separate localization session completed, the full
  focused Orbit widget/wired evidence command passed:
  `flutter test --no-pub test/features/orbit/presentation/widgets/orbital_avatar_test.dart test/features/orbit/presentation/widgets/orbital_visualization_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`.

## final program verdict

Final doc verdict: `closed`

What is accepted:

- visible inner and outer ring orbital friend avatars now call the existing
  Orbit friend chat-opening path for the exact tapped `OrbitFriend`
- orbital avatar actionability is exposed through a friend-specific semantic
  label and a padded 48 px hit target while preserving visual avatar sizes
- the center user avatar and overflow badge remain non-chat-opening
- Orbit friend-row and orbital-avatar chat entry points now share per-friend
  duplicate-open protection in `OrbitWired._onFriendTap`
- route-return friend refresh and background read-marking behavior remain on
  the same shared `OrbitWired._onFriendTap` path
- focused targeted OrbitWired selectors passed:
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "orbital avatar tap pushes exact conversation route and loading shell"`
  - `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --name "(rapid repeated orbital avatar taps|avatar-opened unread friend|blocked and archived contacts|friend tap pushes one conversation route)"`
- after the separate localization session completed, the full focused Orbit
  widget/wired command passed:
  - `flutter test --no-pub test/features/orbit/presentation/widgets/orbital_avatar_test.dart test/features/orbit/presentation/widgets/orbital_visualization_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `git diff --check` passed after implementation
- no repo-owned Orbit blocker remains

Reopen only on real Orbit regression:

- an orbital inner-ring or outer-ring avatar no longer opens the exact tapped
  friend's main 1:1 chat
- rapid repeated avatar or row taps stack duplicate conversation routes
- orbital avatars lose actionable labels or comfortable hit targets
- opening an unread friend from an orbital avatar leaves stale unread state on
  return
- center avatar, overflow badge, blocked/archived boundaries, row opening, or
  lightweight Orbit search/navigation behavior regresses while touching this
  seam
