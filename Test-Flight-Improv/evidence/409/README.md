# Plan 409 evidence — calls in the Orbit rows (2026-09-06)

Orbit ignored calls entirely: a conversation whose most recent event was a call
showed its older message as the preview and sorted by that message, so a
contact you had just missed a call from could sit at the bottom of the ring.

| File | What it proves |
|---|---|
| `dart_orbit_call_activity_green_2026-09-06.txt` | GREEN: 1660 passing, 0 failing across the orbit, feed and call suites |

## What was built

- `OrbitCallActivitySource` (orbit domain port) → `CallHistoryOrbitActivitySource`
  (call data), mirroring how `ConversationCallTimelineSource` is implemented by
  `CallHistoryConversationTimelineSource`. Batched by construction: Orbit
  renders every contact at once, so one query per contact would scale with the
  roster the way the thread summaries and media descriptors deliberately do not.
- `OrbitFriend.latestCall`, set ONLY when the call is newer than the latest
  message, so the preview rule downstream stays a single null check.
- `OrbitFriend.lastActivityAt` — the one recency rule. All three sort sites
  (`load_orbit_data_use_case`, `OrbitItem.sortKey`, `orbit_wired`) now use it.
- `orbitMediaPreviewLabel(call:)` takes precedence over caption, media and the
  deleted placeholder, and reuses `callTimelineStatusLabel` so Orbit and the
  chat row describe one call with the same words.

## The timestamp decision

A call contributes its **end** to Orbit and its **start** to the chat timeline.
Orbit answers "when did this conversation last have activity"; the chat answers
"where does this call sit among the messages". Both are documented at the seam.

## Not included

Unread. A missed call arguably deserves the badge, but "when is a call read?"
needs a read model that does not exist, and inventing one silently would be
worse than leaving the badge message-only.

## Two process notes

`grep -c "^error"` on `flutter analyze` output matches NOTHING — the analyzer
prints `  error •` with leading spaces. That false green hid a genuinely broken
`orbit_wired.dart` (a blanket replace had added `callActivitySource:` to 10
call sites when only 3 accept it). Use `grep -c "error •"`.

`dart format` on a whole directory reformatted 34 orbit files under the 3.47.2
formatter, 31 of them untouched by this work. Format the exact files you
changed, never a directory.

## Device proof — 2026-09-06 00:49Z

`device_proof_2026-09-06.txt`. The Orbit all-chats row shows the call label in
place of the older message text, confirmed on the Pixel.

The first look showed nothing and the capture held no `LOAD_ORBIT_DATA_START`.
A layer census of the capture (FL 956, DB 238, GO 4, **UC 0**) is what made
that absence meaningful — `flow_event_emitter.dart` does no layer filtering, so
UC silence proved the code had not run rather than that logging was off. Cause:
`loadOrbitData` runs on MOUNT, and the screens were open from before the
deploy. A screen that was already open proves nothing about a new build.
