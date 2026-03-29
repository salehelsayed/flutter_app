# Session 40 Plan — Active Upload Progress, Leave Guard, And Wake Lock Across Chat Send Surfaces

## Real Scope

What changes in this session:

- add relay-upload progress delivery from Go to Flutter for `media:upload`
- show an aggregate upload banner in 1:1 and group conversation surfaces while
  a relay upload is active
- show byte progress text plus the foreground warning copy:
  `Keep the app open until the upload completes`
- guard navigation away from the active conversation with a confirmation dialog
  while a relay upload is active
- keep a wake lock enabled for the lifetime of active relay uploads, with a
  ref-count so sequential or overlapping uploads do not flicker the lock

What does not change in this session:

- no receiver-side download progress or wake-lock work
- no true background-upload architecture
- no retry-system redesign
- no widening into non-upload lifecycle work beyond the leave-confirmation seam
- no final closure-doc refresh; that remains Session `41`

---

## Closure Bar

This session is sufficient when all of the following are true:

- Flutter receives byte progress updates for relay media uploads without
  polling
- 1:1 and group conversation screens show a visible upload banner during active
  relay uploads with aggregate `sent / total` bytes and a determinate progress
  bar
- the foreground warning copy is visible while the upload is active
- attempting to leave the conversation while a relay upload is active triggers
  a confirmation dialog
- wake lock enable/disable is tied to active relay-upload lifetime and remains
  held until the last active upload ends
- direct tests prove bridge progress handling, 1:1/group banner behavior, and
  wake-lock lifetime without relying on giant files or real long uploads

---

## Source Of Truth

Authoritative sources for this session:

- proposal and breakdown:
  - `Test-Flight-Improv/22-media-transfer-size-limit.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- regression/gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- upload/send seams:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/core/bridge/bridge.dart`
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/node/media.go`

Conflict rules:

- Session `39` landed attachment-budget work already owns pending-media
  preparation and route hydration; do not reopen it here
- current bridge/event-channel code wins over older media docs where they
  disagree about live progress support, because this session is explicitly
  responsible for adding that support

---

## Current Evidence

- `ConversationWired` and `GroupConversationWired` already bracket upload/send
  flows with `bg:begin` / `bg:end`
- both screens already have `isUploading` and processing state, but there is no
  aggregate upload-progress model, no banner, and no leave-confirmation guard
- `media:upload` is currently one blocking bridge call with no progress push
  event
- there is no wake-lock dependency or shared wake-lock controller in the repo

---

## Files To Touch

Production files:

- `go-mknoon/bridge/events.go`
- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/media.go`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/bridge/p2p_bridge_client.dart` only if helper signatures need
  explicit progress data ownership
- `lib/core/media/` or `lib/core/device/` helper for wake-lock control
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `pubspec.yaml`

Primary tests:

- `test/core/bridge/go_bridge_client_test.dart`
- `test/core/bridge/p2p_bridge_client_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

---

## Planned Verification

Direct tests to run:

- `flutter test test/core/bridge/go_bridge_client_test.dart`
- `flutter test test/core/bridge/p2p_bridge_client_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`

Named gates after direct tests:

- `baseline`
- `1to1`
- `groups`

Stop rule:

- if bridge progress cannot be delivered cleanly through the existing event
  channel without reopening unrelated transport work, stop and record that the
  session is blocked instead of faking byte progress in Flutter
