# Group Chat Core Review Guide

This folder is intentionally reduced to the top 20 core files for reviewing the
group chat path across Flutter bridges, local database persistence, Go/libp2p,
and relay offline delivery. There are no test files, simulator files, harnesses,
UI screens, feed/orbit files, or broad app wiring files in this folder.

All files are flat. A filename encodes its original path by replacing `/` with
`_`.

## Included Files

Flutter bridge and Dart entry points:

- `lib_core_bridge_bridge.dart`: abstract bridge contract and callback surface.
- `lib_core_bridge_bridge_group_helpers.dart`: Dart `group:*` command builders,
  timeouts, and bridge error handling.
- `lib_core_bridge_go_bridge_client.dart`: maps Dart commands to native Go
  platform-channel methods and routes Go events back into Dart.
- `lib_features_groups_application_send_group_message_use_case.dart`: main
  outgoing group message path.
- `lib_features_groups_application_group_message_listener.dart`: receives bridge
  group events and calls incoming handlers.
- `lib_features_groups_application_handle_incoming_group_message_use_case.dart`:
  validates, dedupes, and persists incoming group messages.
- `lib_features_groups_application_drain_group_offline_inbox_use_case.dart`:
  startup/resume missed-message recovery from relay inbox.

Database and repository core:

- `lib_features_groups_domain_repositories_group_repository_impl.dart`: group,
  member, and key repository implementation.
- `lib_features_groups_domain_repositories_group_message_repository_impl.dart`:
  group message repository implementation.
- `lib_core_database_helpers_groups_db_helpers.dart`: SQLite helpers for groups,
  members, and keys.
- `lib_core_database_helpers_group_messages_db_helpers.dart`: SQLite helpers for
  group messages, cursors, statuses, unread counts, and inbox retry fields.
- `lib_core_database_migrations_017_groups_tables.dart`: base group/member/key
  schema.
- `lib_core_database_migrations_018_group_messages_tables.dart`: base group
  message schema.

Go/libp2p and relay core:

- `go-mknoon_bridge_bridge.go`: exported Go bridge commands consumed by Flutter.
- `go-mknoon_node_group.go`: native group config, members, roles, and key state.
- `go-mknoon_node_pubsub.go`: live group publish/subscribe, validation,
  decrypt, and event emission.
- `go-mknoon_node_group_inbox.go`: Go client calls for relay group inbox store,
  retrieve, cursor pagination, and repair ranges.
- `go-mknoon_crypto_group.go`: group symmetric encryption/decryption helpers.
- `go-mknoon_internal_group_envelope.go`: encrypted group wire envelope shape.
- `go-relay-server_group_inbox_store.go`: relay-side group inbox storage and
  retrieval behavior.

## How The Files Connect

Send flow:

`send_group_message_use_case` validates local group/member state through the
repositories, writes an outgoing message through `group_message_repository_impl`,
calls `bridge_group_helpers` to publish via `group:publish`, and stores an
offline replay envelope through `group:inboxStore`.

Flutter-to-Go bridge:

`bridge_group_helpers` builds JSON commands. `go_bridge_client` maps those
commands to native method names. `go-mknoon_bridge_bridge.go` receives the
native calls and delegates to Go node functions.

Live receive flow:

`go-mknoon_node_pubsub.go` receives/decrypts/validates a libp2p group message
using `go-mknoon_node_group.go`, `go-mknoon_crypto_group.go`, and
`go-mknoon_internal_group_envelope.go`. It emits a group event back through the
bridge. `group_message_listener` receives that event and calls
`handle_incoming_group_message_use_case`, which dedupes and persists the message.

Offline recovery flow:

`send_group_message_use_case` stores encrypted replay payloads through the Go
group inbox path. `go-mknoon_node_group_inbox.go` talks to the relay, and
`go-relay-server_group_inbox_store.go` stores/retrieves missed group messages.
On app startup/resume, `drain_group_offline_inbox_use_case` pages missed
messages and sends them through the same incoming-message handler.

Database flow:

The repository implementations translate domain operations into SQLite helper
calls. The two included migrations define the base group and group-message
tables. The helper files are the main place to review row mapping, status
updates, unread counts, cursor persistence, and inbox retry state.

## Test Types To Look For In The Full Repo

The tests are not included here, but the full repo should have coverage in these
areas:

- Bridge contract tests for `group:*` command payloads, errors, timeouts, and
  Go/Dart field-name alignment.
- Repository and DB helper tests for group/member/key persistence, message
  status transitions, unread counts, cursor writes, and migration compatibility.
- Send-path tests for publish success, no live peers, relay inbox fallback,
  retry after failure, and stuck-sending recovery.
- Receive-path tests for duplicate message IDs, self-echo reconciliation,
  membership rejection, stale key epochs, malformed envelopes, and media
  descriptor validation.
- Offline recovery tests for cursor pagination, duplicate relay pages, relay
  failover, corrupt replay payloads, and interrupted drains.
- Go/libp2p tests for pubsub authorization, decrypt failures, key mismatch,
  envelope parsing, group inbox client behavior, and relay group inbox limits.

Use this bundle to find feature gaps by tracing each flow above and asking
whether every success, partial failure, retry, restart, and duplicate-event case
has an explicit test in the full repo.
