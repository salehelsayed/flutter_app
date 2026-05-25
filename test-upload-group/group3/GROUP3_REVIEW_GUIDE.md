# Group Chat Core Review Guide - Group 3

This `group3` folder contains the next 20 core files after the primary bundle
and `group2`. These files focus on domain contracts, repository interfaces,
membership mutation, and reaction send behavior. They are useful when reviewing
whether the implementation has clear boundaries and whether tests cover the
actual data contracts used by the bridge, database, and recovery paths.

There are no test files, simulator files, harnesses, UI screens, feed/orbit
files, push wrappers, binaries, caches, or vendored files here. Filenames are
flat and encode original paths by replacing `/` with `_`.

## Included Files

Domain models:

- `lib_features_groups_domain_models_group_model.dart`: group identity, type,
  metadata, archive/mute/dissolve state, and retention fields.
- `lib_features_groups_domain_models_group_member.dart`: member identity, role,
  key material, joined-at timestamps, and device identities.
- `lib_features_groups_domain_models_group_message.dart`: persisted group
  message shape, status, direction, media, timestamps, and retry metadata.
- `lib_features_groups_domain_models_group_key_info.dart`: local group key and
  key-generation metadata.
- `lib_features_groups_domain_models_group_message_payload.dart`: message
  payload parsing/serialization contract.
- `lib_features_groups_domain_models_group_invite_payload.dart`: invite payload
  contract used during onboarding.
- `lib_features_groups_domain_models_pending_group_invite.dart`: local pending
  invite state.
- `lib_features_groups_domain_models_group_welcome_key_package.dart`: welcome
  key package contract for new members/devices.
- `lib_features_groups_domain_models_group_pending_key_repair.dart`: pending key
  repair state for undecryptable messages.
- `lib_features_groups_domain_models_group_history_gap_repair.dart`: detected
  history-gap repair state.
- `lib_features_groups_domain_models_group_reaction_payload.dart`: group
  reaction payload contract.
- `lib_features_groups_domain_models_group_invite_delivery_attempt.dart`:
  delivery-attempt state for invite observability and retry.

Repository interfaces:

- `lib_features_groups_domain_repositories_group_repository.dart`: group/member
  and key persistence interface.
- `lib_features_groups_domain_repositories_group_message_repository.dart`: group
  message persistence interface.
- `lib_features_groups_domain_repositories_pending_group_invite_repository.dart`:
  pending invite persistence interface.
- `lib_features_groups_domain_repositories_group_pending_key_repair_repository.dart`:
  pending key repair persistence interface.
- `lib_features_groups_domain_repositories_group_history_gap_repair_repository.dart`:
  history-gap repair persistence interface.

Application behavior:

- `lib_features_groups_application_add_group_member_use_case.dart`: adds members
  and updates/syncs group membership state.
- `lib_features_groups_application_remove_group_member_use_case.dart`: removes
  members and enforces membership boundary behavior.
- `lib_features_groups_application_send_group_reaction_use_case.dart`: sends
  group reactions over the group bridge/pubsub path.

## How These Files Connect To Groups 1 And 2

Group 1 contains the main bridge, send, receive, database implementation, and
Go/libp2p delivery path. Group 2 contains invite, key update, retry, rejoin, and
repair support. Group 3 contains the contracts those flows rely on.

- The repository implementation files in Group 1 implement the repository
  interfaces included here.
- The send/receive/recovery use cases in Group 1 read and write the domain
  models included here.
- The invite and key repair flows in Group 2 depend on pending invite, welcome
  key package, group key, pending repair, and history-gap model contracts.
- The database helpers and migrations in Groups 1 and 2 must map rows to these
  model fields without losing state or changing semantics.
- Membership add/remove flows affect the Go group config sent through Group 2's
  config payload and Group 1's Go pubsub validation.
- Group reactions use the same bridge/pubsub/error boundary as group messages,
  but need their own idempotency and replay expectations.

## Review Focus

Use this bundle to look for gaps in:

- model serialization and deserialization compatibility across app versions;
- null/default handling for newly added fields in older databases;
- mismatch between repository interfaces and repository implementations;
- membership role and joined-at semantics used by send/receive validation;
- removed/re-added member boundaries around exact timestamps;
- key generation and pending key repair model states that can get stuck;
- invite delivery attempts that do not reflect real delivery outcomes;
- reaction idempotency, duplicate delivery, and missing replay behavior;
- database row mapping that drops device identity, key epoch, retry, or cursor
  fields.

Expected test categories in the full repo:

- model serialization and frozen payload tests;
- repository interface/implementation contract tests;
- membership add/remove boundary tests;
- pending invite and invite delivery-attempt tests;
- pending key repair and history-gap repair tests;
- reaction send/receive/replay tests;
- migration compatibility tests for fields represented by these models.
