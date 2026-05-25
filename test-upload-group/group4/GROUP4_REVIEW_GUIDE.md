# Group Chat App Experience Review Guide - Group 4

This `group4` folder contains the optional adjacent app-experience layer for
group chat. Groups 1-3 cover the core bridge, database, Go/libp2p, relay,
invite/key/retry, and domain contracts. Group 4 covers the files that make the
feature feel seamless in the app: lifecycle recovery, notification routing,
foreground/background push handling, group media policy/recovery, and the group
conversation wired screen.

There are no test files, simulator files, harnesses, feed/orbit files, binaries,
caches, or vendored files here. Filenames are flat and encode original paths by
replacing `/` with `_`.

## Included Files

Lifecycle recovery:

- `lib_core_lifecycle_handle_app_resumed.dart`: rejoin/recovery work after app
  resume, including group inbox drain and stuck-send recovery wiring.
- `lib_core_lifecycle_handle_app_paused.dart`: pause-time lifecycle behavior
  that can affect group delivery and recovery state.

Notification routing and open handling:

- `lib_core_notifications_active_conversation_tracker.dart`: tracks the active
  conversation so foreground notification behavior can suppress or route alerts.
- `lib_core_notifications_app_root_notification_open.dart`: app-root handling
  for notification opens.
- `lib_core_notifications_notification_open_dedupe_gate.dart`: prevents duplicate
  notification-open handling.
- `lib_core_notifications_notification_route_dispatch.dart`: dispatches parsed
  notification route targets into app navigation.
- `lib_core_notifications_notification_route_target.dart`: route target contract,
  including group targets.

Push handling:

- `lib_features_push_application_background_message_handler.dart`: background
  remote-message entry point.
- `lib_features_push_application_background_push_notification_fallback.dart`:
  fallback local notification behavior for background push.
- `lib_features_push_application_handle_foreground_remote_message_use_case.dart`:
  foreground remote-message handling.
- `lib_features_push_application_handle_initial_remote_message_use_case.dart`:
  cold-start initial notification handling.
- `lib_features_push_application_prepare_notification_open_use_case.dart`:
  prepares a notification tap/open event.
- `lib_features_push_application_prepare_notification_route_target_use_case.dart`:
  converts push payloads into route targets.
- `lib_features_push_application_resolve_group_notification_route_target_use_case.dart`:
  group-specific notification target resolution.
- `lib_features_push_application_show_notification_use_case.dart`: local
  notification presentation.

Media policy and recovery:

- `lib_core_media_group_media_integrity_policy.dart`: validates group media
  integrity metadata.
- `lib_core_media_group_media_mime_policy.dart`: validates allowed group media
  MIME types.
- `lib_core_media_group_media_size_policy.dart`: validates group media size.
- `lib_features_groups_application_retry_incomplete_group_uploads_use_case.dart`:
  recovers incomplete group media uploads.

Group conversation wiring:

- `lib_features_groups_presentation_screens_group_conversation_wired.dart`:
  connects group conversation UI to repositories, bridge callbacks, send logic,
  read state, media, and recovery hooks.

## How These Files Connect To Groups 1-3

- Resume handling calls the rejoin, inbox drain, stuck-send recovery, and upload
  retry flows from Groups 1 and 2.
- Push payloads resolve to group notification route targets, then dispatch to
  group conversation navigation.
- Active conversation tracking prevents duplicate or noisy notifications when a
  group is already open.
- Group media policy protects the send and incoming-message paths from invalid
  media descriptors before persistence or display.
- `group_conversation_wired` is the practical UI integration point over the
  application use cases, repositories, and bridge callbacks included in Groups
  1-3.

## Review Focus

Use this bundle to look for gaps in:

- app resume ordering: bridge rejoin, inbox drain, upload retry, and stuck-send
  recovery should not race into duplicate messages or missed recovery;
- cold-start notification opens where local group state is missing or inbox
  drain has not completed;
- duplicate notification taps and repeated foreground/background payloads;
- foreground suppression when the group conversation is already active;
- push payload shape drift between notification routing and group message data;
- local notification display that claims delivery before the message is locally
  recoverable;
- group media validation mismatches between send, receive, upload retry, and UI
  rendering;
- wired-screen assumptions that duplicate business logic from use cases.

Expected test categories in the full repo:

- resume/pause group recovery tests;
- foreground/background push handling tests;
- notification open and dedupe tests;
- group route target resolution tests;
- cold-start notification-to-group navigation tests;
- group media MIME/size/integrity tests;
- incomplete group media upload retry tests;
- group conversation wired-screen integration tests.
