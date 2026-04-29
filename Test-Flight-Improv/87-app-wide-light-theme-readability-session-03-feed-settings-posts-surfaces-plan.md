# Session 03 Plan: Feed, Settings, and Posts light-background surface closure

## real scope

This session closes the remaining high-traffic non-chat app-shell readability gap for Daylight Lagoon, with implementation focused on Posts because Feed and Settings already have readable-role wiring and direct Daylight coverage from docs `84` and `86`.

Posts scope includes the Posts header, status message, time-section labels, caught-up copy, empty state, post cards, pinned posts summary/cards, metric actions, delivery chips, and media skeleton/voice surfaces.

This session does not change post delivery, nearby filtering, feed handoff, media upload, pin delivery, Settings persistence, or Feed message behavior.

## closure bar

Session 03 is complete when Posts visible content and pinned content consume `BackgroundReadableColors` on Daylight Lagoon, focused Posts widget evidence proves actual content is readable, and focused Feed/Settings/Posts tests pass. Existing Feed/Settings Daylight evidence remains valid.

## source of truth

- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/posts/presentation/screens/posts_screen.dart`
- `lib/features/posts/presentation/widgets/post_card.dart`
- `lib/features/posts/presentation/widgets/pinned_posts_section.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/posts/phase1/posts_screen_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and tests win over stale prose. Named gate membership follows `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## session classification

`implementation-ready`

## exact problem statement

Feed and Settings have already adopted readable roles for the main Daylight paths, but Posts still renders core visible cards and empty/header chrome with fixed dark surfaces and white foregrounds. On Daylight Lagoon, those fixed colors can either look detached from the selected background or leave pale foreground assumptions in related card states.

## files and repos to inspect next

- `lib/features/posts/presentation/screens/posts_screen.dart`
- `lib/features/posts/presentation/widgets/post_card.dart`
- `lib/features/posts/presentation/widgets/pinned_posts_section.dart`
- `test/features/posts/phase1/posts_screen_test.dart`
- Existing Feed and Settings Daylight tests listed above

## existing tests covering this area

- Feed has direct Daylight loading, connection card, and thread header tests in `feed_screen_test.dart`.
- Settings has Daylight selected-state and header tests in `settings_screen_test.dart` and `settings_wired_test.dart`.
- Posts has screen and card tests, but no Daylight readable-role proof for actual post/pinned content.

## regression/tests to add first

Add a Posts screen widget test that renders Daylight Lagoon with one normal post and one pinned post, then asserts the Daylight background appears and actual visible copy uses light-readable foregrounds with sufficient contrast.

## step-by-step implementation plan

1. Import `BackgroundReadableColors` into Posts screen/card/pinned widgets.
2. Replace Posts hardcoded dark-card and white/muted foreground colors with readable surface, border, divider, icon, text, placeholder, and disabled roles.
3. Keep media carousel chrome and action accents intentionally high-contrast where they sit on media/dark overlays.
4. Add the Daylight Posts visible-content test.
5. Run `dart format`.
6. Run focused direct tests:
   - `flutter test test/features/posts/phase1/posts_screen_test.dart`
   - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
   - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`

## risks and edge cases

- Posts screen must read the readable extension from inside `AmbientBackground`, not before it wraps the subtree.
- Pinned see-all route should continue to inherit readable roles.
- Action accents can remain brand colors only when they contrast on the effective surface.
- Existing post behavior tests must not change because this session is presentation-only.

## exact tests and gates to run

- `flutter test test/features/posts/phase1/posts_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`

No named gate is required because this session changes presentation roles only. Run `posts` or `feed` gates only if delivery, privacy, replay, composer, inline reply, or handoff behavior changes; this session must avoid those behavior paths.

## known-failure interpretation

Failures in the three focused widget suites are in scope. Broader integration or device-bound failures are not used to judge this session unless the touched files introduced them.

## done criteria

- Posts screen/card/pinned visible content uses readable roles.
- A Daylight Posts visible-content test passes.
- Existing focused Feed and Settings Daylight screen tests pass.
- Breakdown ledger marks Session 03 accepted with verification.

## scope guard

Do not alter post send, comments, pass-along, pin delivery, nearby eligibility, feed orchestration, Settings persistence, or media upload behavior. Do not migrate compose/comments/pass/edit sheets here beyond the visible Posts screen/card/pinned path; broad transient sheets remain owned by Session 07 if not directly launched from the main Posts screen proof.

## accepted differences / intentionally out of scope

Media carousel counters and page dots remain media-overlay chrome with white foregrounds over dark scrims/media, not selected-background surface text. Full post compose/comment/pass/edit sheets remain explicit transient surfaces for Session 07 unless a direct main-screen test exposes them earlier.

## dependency impact

Session 07 may close remaining post sheets and cross-app transients without reopening the main Posts card path unless a real Daylight regression is found.

