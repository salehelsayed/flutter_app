# Plan 413 evidence — missed-call cards must not arrive while the app is open

Reported 2026-09-06: "notifications arriving after I open the app" — the shape
of a bug the user had fixed days earlier. It was NOT that bug and NOT the
relay: no relay commit or deploy happened in this session, and the newest relay
deploy record predates it. It was the missed-call card added the same evening.

## Evidence

Captures `docker-ws/deploy-captures/fresh-260906021326`, Pixel:

```
02:15:33.349  CONV_FL_SCREEN_INIT
02:15:42.867  MISSED_CALL_NOTIFICATION_POSTED   <-- 9 s later, app in foreground
02:15:42.867  MISSED_CALL_NOTIFICATION_SHOWN
```

## Cause

The composition supplied:

```dart
return visibility.maySuppress;
```

`maySuppress` is true only for the ONE conversation that is visible. But the
call surface is a full-screen overlay above the whole app, so a user anywhere
in the app has already watched the call ring and end. On Orbit or a different
chat, `maySuppress` was false and the card posted.

Fixed to `visibility.isForegroundActive || visibility.maySuppress`.
`AppVisibilityEvaluation.failNotify` still means notify, so a genuinely
backgrounded miss is never lost to a bad visibility read.

| File | What it proves |
|---|---|
| `dart_foreground_suppression_green_2026-09-06.txt` | GREEN: 1468 passing, 0 failing across call, bootstrap, notifications and unit |

TC-413-01..04 pin the whole matrix: foreground elsewhere in the app suppresses,
the same visible conversation suppresses, a backgrounded app still gets the
card, and an unreadable snapshot still gets the card.

## Why the existing tests missed it

TC-406-07 asserted that the notifier suppresses when its injected
`isSuppressed` returns true — the notifier's contract. The defect was in the
RULE the composition supplies to that seam, which no test covered. The message
notification path already consults `isForegroundActive`; only half of it was
copied.
