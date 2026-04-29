# Session 04 Plan: One-to-one Conversation cards, composer, attachments, and message overlays

## real scope

This session closes the one-to-one Conversation visible message/content readability gap for Daylight Lagoon by updating `LetterCard`, upload progress, and attachment preview processing/error states to consume readable roles.

It does not change send, retry, upload ordering, inbox, notifications, reaction persistence, quote/reply behavior, or media picking. Full-screen emoji picker, delete sheets, attachment source sheets, and media viewer chrome remain Session 07 transient surfaces.

## closure bar

Session 04 is complete when actual message cards, quote/unavailable/deleted/failed/status/reaction/timestamp states, upload progress, and attachment processing preview states use readable roles and direct widget tests prove representative-light readability.

## source of truth

- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and tests win over stale prose. Named gate membership follows `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## session classification

`implementation-ready`

## exact problem statement

Conversation already has Daylight header evidence, but message cards and upload/attachment states still rely on fixed translucent white foregrounds and borders. On Daylight Lagoon, message body, sender, quote, timestamp, deleted copy, status icons, upload text, and attachment processing text can be too pale against light readable surfaces.

## files and repos to inspect next

- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`

## existing tests covering this area

`letter_card_test.dart` covers message text, sender, deleted, quote, status, reactions, and failed media actions. `attachment_preview_strip_test.dart` covers thumbnail, uploading, processing, GIF, and remove-button states. They do not currently assert representative-light readable colors.

## regression/tests to add first

Add a LetterCard representative-light test that renders actual mixed-direction content, quote text, reaction, timestamp, transport, and delivered status with readable contrast.

## step-by-step implementation plan

1. Import `BackgroundReadableColors` into the targeted Conversation widgets.
2. Replace message-card background, border, text, muted, quote, timestamp, reaction, status, upload, and attachment processing colors with readable roles.
3. Keep media thumbnails and dark overlay controls as intentional media chrome where they sit over image/video surfaces.
4. Add/adjust representative-light widget assertions.
5. Run `dart format`.
6. Run:
   - `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
   - `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
   - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`

## risks and edge cases

- Status icon colors must remain semantically distinct for failed/pending/delivered.
- Quote unavailable and deleted text must remain identifiable without becoming invisible.
- Attachment media overlay buttons can remain white over intentional dark media scrims.

## exact tests and gates to run

- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`

No `1to1` named gate is required unless shared send/retry/upload/listener/inbox behavior changes; this session is presentation-only.

## known-failure interpretation

Failures in the listed widget/screen suites are in scope. Broader integration failures are not used for this session unless a touched presentation seam causes them.

## done criteria

- Message cards and upload/attachment visible states use readable roles.
- Representative-light LetterCard evidence passes.
- Focused Conversation widget/screen tests pass.
- Breakdown ledger marks Session 04 accepted.

## scope guard

Do not alter message delivery, retry, encryption, persistence, reaction model, media upload state, or route wiring. Do not migrate full emoji picker, context overlay, delete sheets, or full-screen media viewer in this session.

## accepted differences / intentionally out of scope

Image/video thumbnails and controls over dark media scrims remain intentional media chrome. Full transient overlays remain Session 07.

## dependency impact

Session 05 can reuse the same readable-role approach for group message cards. Session 07 will close remaining conversation transients.

