# Group Chat Core Review Guide - Group 2

This `group2` folder contains the next 20 core files after the primary
top-20 bundle in `test-upload-group/`. These files focus on reliability and
security around invites, key updates, retry/recovery, offline replay envelopes,
advanced group database state, and Go event delivery.

There are no test files, simulator files, harnesses, UI screens, feed/orbit
files, push wrappers, binaries, caches, or vendored files here. Filenames are
flat and encode original paths by replacing `/` with `_`.

## Included Files

Flutter application reliability and security:

- `lib_features_groups_application_group_config_payload.dart`: builds the group
  config sent from Flutter to Go for topic validation and membership rules.
- `lib_features_groups_application_group_offline_replay_envelope.dart`: creates
  encrypted replay payloads used by relay inbox recovery.
- `lib_features_groups_application_rejoin_group_topics_use_case.dart`: rejoins
  Go/libp2p group topics after startup or resume.
- `lib_features_groups_application_recover_stuck_sending_group_messages_use_case.dart`:
  repairs local messages left in `sending` state.
- `lib_features_groups_application_retry_failed_group_messages_use_case.dart`:
  retries failed outgoing group sends.
- `lib_features_groups_application_retry_failed_group_inbox_stores_use_case.dart`:
  retries failed relay inbox storage after publish.
- `lib_features_groups_application_group_invite_listener.dart`: receives group
  invite events and routes them into local invite handling.
- `lib_features_groups_application_handle_incoming_group_invite_use_case.dart`:
  validates and persists incoming group invites.
- `lib_features_groups_application_send_group_invite_use_case.dart`: sends group
  invite and key material to invited contacts.
- `lib_features_groups_application_group_key_update_listener.dart`: receives key
  update events and routes valid updates into local state.
- `lib_features_groups_application_rotate_and_distribute_group_key_use_case.dart`:
  rotates group keys and distributes new epoch material.
- `lib_features_groups_application_group_pending_key_repair_service.dart`:
  tracks and retries missing key material needed to decrypt group messages.

Database support:

- `lib_core_database_helpers_pending_group_invites_db_helpers.dart`: pending
  invite storage and lookup.
- `lib_core_database_helpers_group_keys_db_helpers.dart`: group key persistence.
- `lib_core_database_helpers_group_history_gap_repairs_db_helpers.dart`: local
  history-gap repair state.
- `lib_core_database_helpers_group_pending_key_repairs_db_helpers.dart`: local
  pending key repair state.
- `lib_core_database_migrations_051_pending_group_invites.dart`: schema for
  pending group invites.
- `lib_core_database_migrations_063_group_pending_key_repairs.dart`: schema for
  pending group key repairs.

Go bridge/event support:

- `go-mknoon_bridge_events.go`: Go-side event names and event emission helpers.
- `go-mknoon_node_event_dispatcher.go`: event queue/dispatch behavior between
  Go/libp2p and Flutter callbacks.

## How These Files Connect To Group 1

The first bundle covers the direct send, receive, bridge, database, Go pubsub,
and relay inbox path. This second bundle covers the support systems that make
that path reliable:

- `group_config_payload` feeds Go group config used by `go-mknoon_node_group.go`
  and `go-mknoon_node_pubsub.go`.
- Invite listener/send/handle files create the onboarding path before a user can
  receive group messages from the first bundle.
- Key update, rotation, and pending key repair files protect the decrypt path
  used by `handle_incoming_group_message_use_case` and Go pubsub.
- Retry and stuck-send recovery files protect the outgoing path around
  `send_group_message_use_case`.
- Offline replay envelope and inbox retry files support
  `drain_group_offline_inbox_use_case`.
- Database helper/migration files persist invite, key, key-repair, and
  history-gap state that the repositories and recovery flows depend on.
- Go event files determine whether Flutter reliably receives group invite,
  key-update, message, reaction, and failure events.

## Review Focus

Use these files to look for gaps in:

- invite idempotency, invite revocation, stale invite rejection, and duplicate
  invite delivery;
- key epoch rotation, key update ordering, missing-key repair, and replayed key
  package handling;
- retry behavior after app restart, relay outage, or bridge timeout;
- event queue overflow, dropped Go events, ordering issues, and duplicate event
  dispatch;
- DB migration compatibility for pending invites and pending key repairs;
- history-gap and key-repair state that can get stuck without user-visible
  recovery.

Expected test categories in the full repo:

- invite send/receive/accept/revoke/resend tests;
- key update, key rotation, and pending key repair tests;
- stuck-send and failed-inbox-store retry tests;
- resume/rejoin/offline replay tests;
- DB helper and migration tests for invites, keys, history gaps, and key repair;
- Go event dispatcher tests for ordering, pressure, and callback delivery.
