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

## Killed-app history row (gap 4)

A call that arrives while the Android app is dead never reaches
`CallCoordinator`: `androidHeadlessCallAdmissionMain` starts no coordinator by
design. So it wrote NO history row at all, and the chat rendered nothing for
it even after the rows shipped.

`MailboxProductionHeadlessCallAdmissionSession` now takes a
`HeadlessCallHistoryRecorder`. When the admission walk judges the call terminal
(the caller ended it while the app was dead) it captures the invite and
terminal signals and projects the row: `terminate` → `callerCancelled`,
`reject` → `declined`. The composition builds a `CallHistoryProjector` over the
isolate's own database and guards timestamp monotonicity, because the terminal
row can carry an earlier clock than the invite and `CallHistoryEntry` refuses
to construct on a non-monotonic pair.

| File | What it proves |
|---|---|
| `dart_headless_history_green_2026-09-05.txt` | GREEN: 1397 passing, 0 failing; TC-406-30 records a killed-app cancel, TC-406-31 records nothing for an admitted call (the foreground owner still projects it, so no double row), TC-406-32 keeps the disposition when the recorder throws |

**Deliberately not done:** the killed-app case still posts no missed-call
*card*. That needs this isolate to initialise its own
`FlutterLocalNotificationsPlugin`, the way `background_message_handler.dart`
does, and is only verifiable on a device. The user is not left with nothing —
the incoming call still rings and its notification is shown — but the call is
not summarised afterwards.

## Device proof — 2026-09-05 21:35-21:40Z

`device_proof_2026-09-05.txt`, captures `fresh-260905233249`, build
`38362fd48`. The notification posts on BOTH platforms (`status=cancelled`,
the callee's view of a caller who hung up before the answer), suppression
holds while the conversation is visible, and every suppressed case still
logged its `CALL_TERMINAL_CLEANUP_RESULT` — the row was projected, only the
card was withheld.

The killed-app row is proven too: after the app was killed (pid 17974 gone,
`stopped=false`), a new process (19395) ran `HeadlessCallAdmissionWorker` to
SUCCESS for three calls and the row was present on reopening.

Still unverified: the plan-407 ring drain and the iOS `.unanswered` Recents
badge.
