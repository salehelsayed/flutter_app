# Session 06 - Share, QR, Introduction, And Identity Surfaces Plan

## Scope
- Share target picker content, search, preview, loading/empty, selected rows, and send overlay.
- QR display surface and its reusable QR/scan/empty-circle widgets under selected backgrounds.
- Create group/contact picker selected-background entry surfaces and shared picker rows/panel.
- Identity choice onboarding when rendered with a selected background.
- Explicit classification for introduction friend picker/sent confirmation, QR scanner, mnemonic input, and identity progress where they remain intentionally dark or platform-default.

## Closure Bar
- Selected-background surfaces use `BackgroundReadableColors` from the `AmbientBackground` subtree.
- Intentionally dark/pre-preference surfaces are documented and remain readable on their own effective surface.
- Focused widget tests cover representative Daylight content for share, QR display, group pickers, and identity choice.

## Out Of Scope
- QR scanner camera chrome and introduction bottom-sheet internals beyond classification remain candidates for Session 07 or final simulator evidence if a visual regression appears.
