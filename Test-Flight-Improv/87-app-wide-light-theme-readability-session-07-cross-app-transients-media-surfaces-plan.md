# Session 07 Plan: Cross-App Transients And Media Surfaces

- Source doc: `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- Breakdown: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Session id: `07-cross-app-transients-media-surfaces`
- Status: implemented and verified in local fallback pipeline

## Scope

Close the remaining high-risk transient surfaces that can appear while a selected light background is active:

- contact request dialogs
- one-to-one and group attachment source sheets
- one-to-one context menus, quick reactions, and full emoji picker
- group reaction detail sheet
- group metadata editor dialog
- Orbit confirmation danger action
- QR scanner success and paste dialog actions
- full-screen media viewer classification

Persistent screen content remains owned by Sessions 02 through 06. Camera/scanner and full-screen media chrome may remain intentionally dark only when readable on that effective dark surface.

## Implementation Contract

- Reuse `BackgroundReadableColors` for selected-background dialogs, sheets, menus, reaction details, input fields, dividers, and icons.
- Preserve existing dark media/camera behavior where the surface is explicitly dark.
- Fix any destructive or primary action foreground/background pairs that fail contrast on their actual effective surface.
- Avoid behavior changes for scanning, contact requests, attachment picking, reactions, group metadata updates, deletion, or media viewing.

## Verification Contract

Required direct tests:

- `flutter test test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart`
- `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `flutter test test/features/conversation/presentation/widgets/full_emoji_picker_test.dart`
- `flutter test test/features/groups/presentation/widgets/group_reaction_details_sheet_test.dart`
- `flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `flutter test test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
- `flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- `flutter test test/features/qr_code/presentation/widgets/scan_overlay_test.dart`

Compile/behavior guard for wider wired surfaces touched by this session:

- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_gif_test.dart test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart`

## Closure Bar

Session 07 is accepted when the direct tests above pass and doc `87` records which transient/media surfaces are now role-backed versus intentionally dark. Any simulator-only camera/media visual proof moves to Session 08 final acceptance rather than blocking this session.
