# Plan 407 evidence — ring-time call mailbox drain (2026-09-05)

## The device failure

iPhone 11 → iPhone 13, caller cancelled before answer, callee kept ringing
until the user declined by hand nine seconds later. Captures
`docker-ws/deploy-captures/fresh-260905231926`:

| Time (UTC) | Device | Event |
|---|---|---|
| 21:21:02 | iPhone 11 | invite stored, `wake: "dispatched"` |
| 21:21:03 | iPhone 13 | wake drained, `systemUiPresented` — ringing |
| 21:21:05 | iPhone 11 | cancel; terminate stored, **`wake: "none"`**, `directAccepted: false` |
| 21:21:07, :10 | iPhone 11 | `direct_send result: false` — both retries fail |
| 21:21:14 | iPhone 13 | user declines by hand; first transition since 21:21:03 |

The iPhone 13 logged NO transition between 03 and 14: it never learned the
call was cancelled.

## Cause

`recipientAttached` (`go-relay-server/call_control_redis.go:736`) returns true
once `meta.AckedEvents > 0`. The callee acked the invite, so the relay
deliberately sent no wake for the terminate. That rule is correct and
device-proven — waking once per event of a caller's offer/ICE burst made
CallKit re-present the call — but it assumes the attached recipient's live
connection carries the rest. Here every direct leg failed, and the callee only
drains its mailbox when woken.

Not a regression from 405/406: those touch history and notifications, which run
after signal delivery, and the failure is in delivery itself.

## Fix

`RingingCallMailboxPoller` drains the call mailbox every 2 s while a call is
ringing, in either direction — a callee's `reject` can be skipped for an
attached caller exactly as this `terminate` was. Chosen over a relay-side
change because it covers every cause of a missed live delivery, needs no
production relay deploy, and leaves the burst rule the attached check exists to
protect untouched.

The drain is narrower than `onCallWake`: it never starts the graph, so a poll
can only read a mailbox the ringing call already proves is live.

| File | What it proves |
|---|---|
| `dart_ring_drain_green_2026-09-05.txt` | GREEN: 839 passing, 0 failing across the call and bootstrap suites |

TC-407-01..10 cover the ways this could do harm rather than good: a slow drain
never stacks, a throwing drain keeps polling, staying in `ringing` does not
restart the timer (which would reset the interval on every unrelated snapshot
and starve the drain), and it stops on connect, end, null session, dispose and
composition shutdown.

TC-407-02 first failed because the test fired two ticks synchronously, which
the anti-stacking guard correctly collapses. The test was fixed, not the guard:
real ticks are an interval apart.
