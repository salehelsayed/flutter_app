# Session 08 Plan: Acceptance, Visual/Simulator Evidence, And Closure

- Source doc: `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- Breakdown: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Session id: `08-acceptance-visual-simulator-closure`
- Status: final acceptance session

## Scope

Reconcile the accepted Session 01 through 07 evidence, run the final direct test batch, and persist the final doc verdict. This session does not reopen surface implementations unless the acceptance batch exposes a real regression.

## Acceptance Batch

Run representative direct tests across every accepted surface family:

- readability contract and helper evidence
- Orbit visible content and confirmation dialog
- Feed, Settings, and Posts
- one-to-one Conversation cards, attachments, overlays, emoji picker, media viewer, and wired compile/behavior guard
- Group list, cards, info, conversation, reaction details, and wired compile/behavior guard
- Share, QR display/scanner, Contact/Create Group Picker, Identity Choice, Introduction, Mnemonic Input, and Identity Progress

Named gates are not required because this rollout changes presentation roles and focused widget behavior, not gate definitions or durable behavior flows. `Test-Flight-Improv/02-integration-test-coverage.md` does not need a durable coverage update unless a new integration test is added.

## Visual/Simulator Classification

Local widget tests can close readable roles and dark-surface contrast. Simulator/device-only evidence remains explicit follow-up for:

- camera scanner framing and permission overlays
- physical keyboard/search focus placement
- system status/navigation chrome
- route transition screenshots
- device-specific media player chrome

## Closure Bar

Session 08 may close as `accepted_with_explicit_follow_up` when all direct tests pass and only simulator/device visual proof remains. It must be `blocked` if a direct test or compile guard fails.
