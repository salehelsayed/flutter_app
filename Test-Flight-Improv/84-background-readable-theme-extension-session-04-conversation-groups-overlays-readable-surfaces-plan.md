# Session 04 Plan: Conversation, Orbit, And Overlay Representative Surfaces

## real scope

Migrate representative non-Feed shared-background surfaces without touching messaging, group, intro, or transport behavior.

## closure bar

Conversation header and one Group/Orbit representative loading/empty state consume readable roles under representative light coverage.

## source of truth

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `lib/features/conversation/presentation/widgets/conversation_header.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`

## session classification

`implementation-ready`

## exact problem statement

Conversation header and Orbit helper/loading states had dark-background-only white/dark colors, leaving representative non-Feed shared surfaces unproven for light readability.

## files and repos to inspect next

- `test/features/conversation/presentation/widgets/conversation_header_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

## existing tests covering this area

Conversation header tests covered copy/icons/callbacks. Orbit loading tests covered placeholder visibility and chrome layout. Neither checked readable roles.

## regression/tests to add first

Add representative light role assertions for Conversation header text/icons/gradient and Orbit loading rows.

## step-by-step implementation plan

1. Convert Conversation header gradient, back/overflow icons, title, and date to readable roles.
2. Convert Orbit intro/no-result helper copy and loading placeholders to readable roles.
3. Add tests for representative light role usage.

## risks and edge cases

Do not alter send/retry/upload/listener/inbox, intro acceptance, group invite, group messaging, or Orbit row action behavior.

## exact tests and gates to run

- `flutter test --no-pub test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- No named `1to1`, `groups`, `intro`, or `transport` gate required because only presentation colors changed.

## known-failure interpretation

Any messaging/group gate failure would be unrelated unless code changes widen beyond presentation colors.

## done criteria

Representative non-Feed surfaces use readable roles and targeted widget tests pass.

## scope guard

Do not change message delivery, retry, group recovery, intro state, search behavior, or row action semantics.

## accepted differences / intentionally out of scope

Dialogs, bottom sheets, media pickers, message overlays, and exhaustive group screen color migration remain explicit follow-up before shipping a production light background.

## dependency impact

Session `05` must record the follow-up inventory gap rather than claiming exhaustive shared-surface closure.

## closure result

`accepted_with_explicit_follow_up`

Evidence:

- Updated `lib/features/conversation/presentation/widgets/conversation_header.dart`.
- Updated `lib/features/orbit/presentation/screens/orbit_screen.dart`.
- Extended Conversation header and Orbit loading tests.
- Passing focused surface suite including Conversation and Orbit tests.
