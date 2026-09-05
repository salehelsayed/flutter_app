# Plan 406 evidence — missed-call notification (2026-09-05)

Neither platform tells the user about a call they never took.

- **Android** runs self-managed Telecom (`androidx.core.telecom.CallsManager`).
  Self-managed calls never enter the system call log and the platform posts no
  missed-call notification; the incoming card is simply cancelled
  (`MknoonCallAndroidRuntime.kt:952`) and nothing replaces it.
- **iOS** CallKit reported a remote cancel as `.remoteEnded`
  (`MknoonCallKitController.swift:780`), which reads as an ordinary ended call
  in Recents. `.unanswered` is the reason that marks it missed, and it was
  used only for local expiry.

| File | What it proves |
|---|---|
| `dart_missed_call_green_2026-09-05.txt` | GREEN: 1976 passing, 0 failing across the call, notification, bootstrap and push suites |

## What was built

- `MissedCallNotifier` (`lib/features/call/application/`) owns the policy:
  incoming only; `missed`/`cancelled`/`busy` only (`declined` is the user's own
  action and would be noise); never on a replayed projection; suppressed while
  that conversation is visible, because the call row already appears there
  live. It never throws — a call must not fail because a card could not show.
- A dedicated `mknoon_calls` channel with `AndroidNotificationCategory.missedCall`
  so calls and chat silence independently, plus a `mknoonNotificationChannels`
  census that `ensureMknoonNotificationChannel` now iterates. A channel that is
  never created posts nothing at all on Android 8+.
- `NotificationService.showMissedCallNotification` with a `call:`-namespaced
  deterministic id, so a missed call never replaces the message card for the
  same contact.
- Copy in en/ar/de through `notificationPreviewLocalizations`, which needs no
  BuildContext — the projection can run in a background isolate.
- iOS `remoteCancel` now reports `.unanswered` when `answeredCallIds` does not
  contain the call; an answered call ended remotely keeps `.remoteEnded`.
  **Swift is not unit-testable in this container** — compile-verified only,
  device check outstanding.

The notifier hangs off the same `CallHistoryProjector.onTerminalProjected` hook
the chat refresh uses. The hook now reports whether the row was newly inserted,
which is what stops a replay from re-notifying.

Two pre-existing tests asserted exactly two notification channels; both were
re-pinned to the census (three) with a written rationale, never weakened.
