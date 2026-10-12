# SE-41 T4a: background update check

The app checks the signed version file in the background and posts a reminder
when an update is available or required. The signed file is the only authority
(`UpdateCheckService.check()`). The kill switch and the release guard are the
same as T1: E2E, SIMS, the debug default and `MKNOON_UPDATE_CHECK=off` schedule
nothing and cancel any earlier schedule.

## How it runs

| | iOS | Android |
|---|---|---|
| Trigger | BG app refresh task `com.mknoon.app.update-check`, about every 12 h | Unique periodic WorkManager work `mknoon-se41-update-check`, about every 12 h, network required, `KEEP` |
| Engine | The normal main engine | The main engine (handoff) while it holds the canonical runtime lease; a minimal engine when the lease is free; otherwise deferred |
| Dart entry | `UpdateCheckBackgroundRunner.run` | Same |
| Budget | 22 s in Dart, 25 s native | 18 s in Dart, 20 s native |
| Tap | Opens the app; Dart opens `https://apps.apple.com/app/id6760883540` | Opens `https://play.google.com/store/apps/details?id=com.mknoon.app` directly |

Code: `lib/features/update_check/background/`,
`ios/Runner/UpdateCheckBackgroundTask.swift`,
`android/app/src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt` and
`UpdateCheckNotificationPoster.kt`.

## Reminder rules

- Soft (installed < latestBuild): once per latestBuild.
- Hard (installed < minBuild): once, then daily for 7 days, then weekly. A
  higher minBuild starts over. A clock that went back makes it due.
- Never in the foreground, never during a call, never when the build is
  current. One fixed id per kind, so a reminder replaces the last one.
- The app never asks for notification permission for this. Without it, the
  run skips silently.

## Limits

- iOS runs the task only when the system decides to. It never runs after the
  user force-quits the app, and not when Background App Refresh is off.
- Android Doze, App Standby buckets and OEM battery savers can delay the work
  for hours or longer.
- The 6 h gate of the foreground check also applies to background runs: if the
  last attempt (a failed download included) is less than 6 h old, the run
  uses the stored file and downloads nothing.
- Before the first unlock after a reboot (iOS) the state file cannot be read.
  The run is skipped; the state is never reset.
