# Plan 238 Session 238-01 — Policy, DB v101, encrypted wire, and safe-disabled authoring

Status: execution-in-progress
Source: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 238-01
Run mode: implementation + host/Go structural proof
Dependencies: Plan 234 Sessions 01–06 and overall Plan 234 are accepted/closed; DB v100 is landed
Migration owner: Plan 238 exclusively owns sequential DB v101

## Objective

Land the compatibility foundation for discussion-group private media without
shipping a partially enforced feature:

1. freeze and migrate the exact message-scoped v101 policy/local-state seed;
2. add typed policy parsing whose legacy absence is ordinary and whose explicit
   invalid/unknown value is durable fail-closed `unsupported`;
3. carry only the four sender policy fields through the existing encrypted
   group `extra` map across send, retry, live receive, and offline replay;
4. pre-persist/revalidate the exact current discussion-group policy before any
   upload, publish, or inbox work; and
5. keep production availability off while applying the minimum receive/action/
   library/retry shields needed to prevent an early future-client private
   payload from leaking through ordinary group behavior.

Session 238-01 does not implement consume, expiry scheduling, cleanup, enabled
private viewing, final notification UX, platform protection, or device
acceptance. Those remain Sessions 238-02 through 238-04.

## Planning Grounding

- `AGENTS.md` governs dirty-tree preservation, Graphify usage,
  availability-bounded devices, and gate cadence.
- The main-agent Graphify TDD queries anchored `GroupMessage`,
  `retryFailedGroupInboxStores`, and
  `storeGroupOfflineReplayFromRetryPayload`. The graph reported
  `confidence=anchored` but stale topology at `lib/main.dart`; every load-
  bearing conclusion below was reverified in current source.
- Current database head and both production migration registries end at v100.
  No competing v101 implementation, migration, test, or owner exists.
- The intended `GroupMessagePayload` model and
  `presentation/widgets/group_compose_area.dart` named by the older breakdown
  are not live production entry points. The actual send/receive path is
  `send_group_message_use_case.dart` -> `bridge_group_helpers.dart` -> the
  narrow Go bridge parameter map -> generic encrypted group extras -> live
  listener/offline drain -> `handle_incoming_group_message_use_case.dart`.
  The actual composer is `GroupConversationWired` ->
  `GroupConversationScreen` -> shared `ComposeArea`.
- `retry_failed_group_inbox_stores_use_case.dart` is a required re-drive seam:
  it currently replays persisted inbox payloads without reloading current
  group/membership authorization.
- Current group receipt can emit ordinary sender/body notification copy and
  auto-download media, and current Shared Media SQL has no private group-parent
  predicate. Merely persisting v101 fields without negative shields would be a
  privacy regression before Session 238-03.

## Accepted Plan-238 Policy Contract

- Scope is `GroupType.chat` only. Announcement and QA authoring/surfaces stay
  ordinary and unchanged.
- Private policy is message-scoped and valid only for exactly one image or
  video; no GIF/audio/file, second attachment, text/caption, quote, edit, or
  Forward provenance is eligible.
- Wire policy version 1 contains exactly:
  `mediaPolicyVersion`, `mediaLifecycle`, `mediaDurationSeconds`, and
  `mediaProtected`.
- A valid v1 tuple contains all four keys. For protected-only and View Once,
  `mediaDurationSeconds` is present with explicit JSON `null`; omission is not
  equivalent to null. Dart checks key presence with `containsKey`, and the Go
  decoder preserves absent-vs-null before emitting a canonical null into the
  encrypted extras.
- Wire lifecycle tokens are `standard`, `viewOnce`, and `disappearing`.
  `standard + protected=true` is protected-only. View Once and Disappearing
  require protection. Disappearing durations are exactly `3600`, `86400`, or
  `604800` seconds.
- Absence of all four fields is legacy ordinary. An explicit unknown version,
  unknown lifecycle, wrong type, partial tuple, invalid duration, forbidden
  attachment/message combination, or inconsistent protection bit becomes
  local typed `unsupported`; it never falls back to ordinary.
- Numbers and booleans are strict: bool/int/string/double coercion is forbidden.
  A partial tuple, explicit null for a required non-null field, or a
  non-integer numeric version/duration is unsupported on receive and rejected
  on local send.
- Consumption/expiry is device-local. No consume receipt, sibling-device
  event, global-once claim, relay authority, or remote revocation is added.
- Every current active member who may write an ordinary discussion message may
  choose a supported private policy once availability is enabled. Qualification
  is repeated at selection, before upload, at dispatch, and at every automatic
  or manual retry/re-drive. Revocation returns `unauthorized` with zero upload,
  publish, or inbox-store work for the private row.
- Until Session 238-03 explicitly enables the feature, production authoring is
  hidden/denied. Test-only dependency injection may enable policy composition
  to prove compatibility, but no production default may do so.

## Frozen DB v101 Contract

Migration file:
`lib/core/database/migrations/101_group_private_media_lifecycle.dart`.
Structural test:
`test/core/database/migrations/101_group_private_media_lifecycle_test.dart`.

All timestamp columns below are nullable UTC Unix epoch milliseconds encoded
as SQLite `INTEGER`; no ISO text is stored in these v101 fields.

| Column | Exact SQL | Meaning |
|---|---|---|
| `media_policy_version` | `INTEGER NOT NULL DEFAULT 0 CHECK (typeof(media_policy_version) = 'integer' AND media_policy_version >= 0)` | `0` legacy ordinary; `1` valid v1; an unknown nonnegative source version may be retained only with `media_lifecycle='unsupported'`. |
| `media_lifecycle` | `TEXT NOT NULL DEFAULT 'standard' CHECK (media_lifecycle IN ('standard','view_once','disappearing','unsupported'))` | Durable normalized database token; wire camelCase is never stored. |
| `media_duration_seconds` | `INTEGER CHECK (media_duration_seconds IS NULL OR (typeof(media_duration_seconds) = 'integer' AND media_duration_seconds IN (3600,86400,604800)))` | Present only for valid disappearing state. |
| `media_protected` | `INTEGER NOT NULL DEFAULT 0 CHECK (media_protected IN (0,1))` | Normalized local protection bit. |
| `media_received_at` | `INTEGER CHECK (media_received_at IS NULL OR (typeof(media_received_at) = 'integer' AND media_received_at >= 0))` | Durable local lifecycle anchor: receiver commit time for incoming rows and first custody-success time for outgoing rows. The historical column name is retained, but this two-direction meaning is frozen before RED. |
| `media_expires_at` | `INTEGER CHECK (media_expires_at IS NULL OR (typeof(media_expires_at) = 'integer' AND media_expires_at >= 0))` | Immutable local expiry deadline. |
| `media_last_checked_at` | `INTEGER CHECK (media_last_checked_at IS NULL OR (typeof(media_last_checked_at) = 'integer' AND media_last_checked_at >= 0))` | Persisted local clock high-water. |
| `media_consumed_at` | `INTEGER CHECK (media_consumed_at IS NULL OR (typeof(media_consumed_at) = 'integer' AND media_consumed_at >= 0))` | Device-local View Once terminal timestamp. |
| `media_expired_at` | `INTEGER CHECK (media_expired_at IS NULL OR (typeof(media_expired_at) = 'integer' AND media_expired_at >= 0))` | Device-local disappearing terminal timestamp. |
| `media_cleanup_pending` | `INTEGER NOT NULL DEFAULT 0 CHECK (media_cleanup_pending IN (0,1))` | Retryable local cleanup obligation. |

Index:

```sql
CREATE INDEX idx_group_messages_private_media_expiry
ON group_messages(media_expires_at);
```

The migration uses `PRAGMA table_info(group_messages)` and `sqlite_master` to
add only missing columns/index, runs twice safely, and is registered in both
production create/upgrade paths immediately after v100. It never rebuilds the
table, mutates existing v1–v100 values, changes `media_attachments.owner_lane`,
or touches direct rows. Every legacy group row becomes exactly version 0 /
standard / duration null / protected 0 / all timestamps null / cleanup 0.

Cross-column normalization is application authority rather than a table
rebuild:

- version 0 is ordinary only when lifecycle is standard, duration is null,
  protected is 0, and all local lifecycle fields are null/zero;
- valid version 1 protected-only is standard + duration null + protected 1;
- valid version 1 View Once is view_once + duration null + protected 1;
- valid version 1 Disappearing is disappearing + an allowed duration +
  protected 1;
- explicit invalid/unknown wire input is normalized before insert to retained
  nonnegative source version (or 0 if no valid integer exists), lifecycle
  unsupported, duration null, protected 1, and no expiry/consume terminal
  claim;
- any inconsistent durable tuple loaded from SQL hydrates as typed unsupported
  and stays redacted/denied. It is never treated as ordinary.

## Session-Owned Safe-Disabled Boundary

The central availability dependency defaults to `false` in production.
While false:

- composer controls are absent and dispatch rejects private policy;
- received valid-private or unsupported policy is persisted before any
  derivative decision but renders only a generic unavailable placeholder;
- no private/unsupported notification body, thumbnail, download, decrypt,
  ordinary viewer entry, action dispatch, bookmark, or batch action occurs;
- group Shared Media SQL excludes every nonordinary/unsupported group parent
  before keyset filtering and `LIMIT`;
- cached Shared Media entries never authorize mutation: single bookmark and
  batch bookmark/clear/egress reload the exact group/message/attachment parent
  immediately before dispatch, and bookmark SQL atomically repeats the
  current-ordinary-parent predicate;
- automatic/manual retry and failed-inbox re-drive reload the exact current
  parent/group/member policy before upload/publish/inbox work;
- ordinary legacy group messages, reactions, announcements, direct messages,
  and same-ID direct/unresolved siblings retain existing behavior.

The final generic `New private media` notification and enabled placeholder/
Info UX remain Session 238-03. Suppression while availability is false is the
minimum privacy-safe compatibility behavior, not the final product surface.

## Exact Scope

### New production files

- `lib/core/database/migrations/101_group_private_media_lifecycle.dart`
- `lib/features/groups/domain/models/group_private_media_policy.dart`
- `lib/features/groups/application/group_private_media_availability.dart`

### Existing production files allowed to change

- `lib/core/database/app_database_version.dart`
- `lib/core/database/production_migration_registry.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/bridge/bridge.go`
- `lib/core/database/helpers/media_library_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/group_received_media_action_policy.dart`
- `lib/features/groups/application/group_received_media_actions.dart`
- `lib/features/groups/application/group_media_forward_policy.dart`
- `lib/features/groups/application/group_shared_media_library_controller.dart`
- `lib/features/groups/application/group_shared_media_batch_actions.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- `lib/main.dart` (only the causally proven repository/retry dependency wires
  described below)

`GroupMessagePayload` and `presentation/widgets/group_compose_area.dart` are
not authorized merely by the stale shortlist. Source verification after the
planning review proved that `lib/main.dart` is load-bearing for exactly two
Session-01 dependency seams: injecting the current-parent-qualified group
bookmark capability into `MediaAttachmentRepositoryImpl`, and supplying the
current `GroupRepository`/`IdentityRepository` to both production
`retryFailedGroupInboxStores` call sites. Only those constructor/call-site
wires are authorized; no migration callback, lifecycle implementation,
composer, native, notification, or later-session edit is permitted there.
An independent foundation counterexample review also proved the batched group
thread summary/preview projections and Orbit adapter load-bearing: omitting the
v101 tuple there launders a current private parent into legacy ordinary and can
request body/thumbnail derivatives. Their exact projection/mapping/redaction
seams above are therefore authorized; no broader Orbit UI change is allowed.

### New causal tests

- `test/core/database/migrations/101_group_private_media_lifecycle_test.dart`
- `test/features/groups/domain/models/group_private_media_policy_test.dart`
- `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart`
- `test/features/groups/application/group_private_media_safe_disabled_boundary_test.dart`
- `test/features/groups/application/group_private_media_retry_qualification_test.dart`
- `test/features/groups/application/group_private_media_preupload_boundary_test.dart`
- `test/features/groups/application/group_private_media_stale_library_boundary_test.dart`
- `test/features/groups/integration/group_private_media_transport_boundary_test.dart`
- `test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart`

### Existing focused tests expected to change or preserve

- `test/core/database/integration/full_migration_chain_test.dart`
- `test/core/database/migrations/100_direct_private_media_lifecycle_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/features/groups/domain/models/group_message_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/orbit/application/load_orbit_groups_use_case_test.dart`
- `test/features/groups/application/announcement_media_library_batch_actions_test.dart`
- `test/features/groups/shared_media_test_fakes.dart`
- `test/features/groups/presentation/group_shared_media_go_to_message_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/application/load_group_feed_snapshot_use_case_test.dart`
- `test/features/feed/application/load_feed_use_case_test.dart`
- `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart` (fixture wiring only;
  its live CLI/device run remains conditional and receives no host credit)
- send, failed-send retry, incomplete-upload retry, failed-inbox-store retry,
  incoming handler, listener, offline drain, bridge helper, group action policy,
  conversation screen/wired, Shared Media SQL/repository, announcement
  preservation, and Go bridge/node generic-extra tests directly touched by the
  implementation.

### Registration/docs

- `scripts/run_test_gates.sh` (`GROUP_TESTS` registration only; do not execute)
- `scripts/run_host_test_gates.sh` if exact host inventory registration is
  required
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`
- `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`
- this session plan

## Strict Non-Goals

- No DB v102, competing migration, schema rebuild, attachment lifecycle schema,
  or Plan-242 migration.
- No consume/open CAS, expiry scheduler, backward-clock enforcement, cleanup
  engine, restart convergence, or private storage implementation (238-02).
- No enabled private viewer, final action/Info/reply UX, final notification
  presentation, native Android/iOS protection, or actual PiP (238-03 or
  excluded Plan 243).
- No SQLCipher/device/Android-pair/platform acceptance or overall Plan-238
  closure (238-04).
- No announcement/QA private behavior, Go node/libp2p/relay protocol or
  retention change, consume receipt, account-wide state, remote revocation, or
  exported-copy promise.
- No work on excluded Plans 242, 243, 248, 254, 241, or 253.
- No full `host-all`, `core-host-all`, or `feature-host-all` for this session.

## RED-First Contract

Capture a fresh scoped status/hash manifest after unrelated writers and gates
settle. Add each new causal test before the production seam it requires.

First REDs, in order:

```bash
flutter test test/core/database/migrations/101_group_private_media_lifecycle_test.dart \
  --plain-name 'GPL-01 v101 preserves v100 and adds constrained group private lifecycle idempotently'

flutter test test/features/groups/domain/models/group_private_media_policy_test.dart \
  --plain-name 'GPL-02 legacy absence is ordinary and explicit invalid policy is durable unsupported'

flutter test test/features/groups/integration/group_private_media_payload_roundtrip_test.dart \
  --plain-name 'GPL-04 private policy roundtrips send retry live and offline without local lifecycle leakage'

flutter test test/features/groups/application/group_private_media_safe_disabled_boundary_test.dart \
  --plain-name 'GPL-04A availability off suppresses private derivatives before every ordinary seam'

flutter test test/features/groups/application/group_private_media_retry_qualification_test.dart \
  --plain-name 'GPL-03 private retries requalify current discussion membership before upload or fanout'

flutter test test/features/groups/application/group_private_media_preupload_boundary_test.dart \
  --plain-name 'GPL-03A private parent is durable and requalified immediately before initial and retry upload'

flutter test test/features/groups/application/group_private_media_stale_library_boundary_test.dart \
  --plain-name 'GPL-09A stale ordinary library entries cannot bookmark batch or egress a current private parent'

flutter test test/features/groups/integration/group_private_media_transport_boundary_test.dart \
  --plain-name 'GPL-16 policy uses encrypted extras only and changes no node relay or announcement authority'
```

The missing API/behavior must be the failure. A fixture/import/environment
failure does not count as causal RED. Preserve the raw RED command/result in
`## Execution Progress` before adding production.

## Implementation Order

1. Synchronize the source/breakdown/index to the already accepted Plan-238
   decision contract, landed v100, reserved v101, live entry points, and
   Session-01 unblocked state.
2. Land migration/model parsing/mapping with legacy and owner-collision proof.
3. Land sender policy through the live Dart/Go bridge encrypted-extra path;
   include policy in durable pre-persist identity/reuse checks and preserve
   absent-vs-explicit-null through both languages.
4. Add exact qualification before upload, dispatch, manual/automatic send
   retry, incomplete-upload retry, and failed-inbox-store re-drive. Preserve
   ordinary and reaction retry behavior. Private qualification must not reuse
   the ordinary permissive fallback: missing group, dissolved/non-chat group,
   missing identity, empty roster, removed/inactive self, read-only permission,
   or roster-read failure all deny before work; an active ordinary-writer role
   remains eligible. Durably save and reload the exact policy-bearing
   optimistic parent immediately before initial/incomplete-retry upload;
   save/reload mismatch or authorization loss produces zero upload.
5. Add receipt parsing/persist-before-derivative ordering across live/offline
   paths.
6. Add production-off availability and the minimum notification/download/
   viewer/action/library/presentation shields. Test-only enablement may prove
   composition but production default remains off.
7. Register exact new tests/docs, then run every acceptance command below
   except the explicitly user-skipped `run_test_gates.sh` family.

## Acceptance Gates

### Policy, migration, and model

```bash
flutter test \
  test/core/database/migrations/101_group_private_media_lifecycle_test.dart \
  test/core/database/migrations/100_direct_private_media_lifecycle_test.dart \
  test/core/database/integration/full_migration_chain_test.dart

flutter test \
  test/features/groups/domain/models/group_private_media_policy_test.dart \
  test/features/groups/domain/models/group_message_test.dart
```

### Send/retry/wire/receive

```bash
flutter test \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart \
  test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart \
  test/features/groups/application/group_private_media_retry_qualification_test.dart \
  test/features/groups/application/group_private_media_preupload_boundary_test.dart

flutter test \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/integration/group_private_media_payload_roundtrip_test.dart

flutter test test/core/bridge/bridge_group_helpers_test.dart

(cd go-mknoon && GOTOOLCHAIN=go1.25.0 \
  go test ./bridge ./node -run 'GPL12|GK030' -count=1)
```

### Safe-disabled and ordinary/announcement preservation

```bash
flutter test \
  test/features/groups/application/group_private_media_safe_disabled_boundary_test.dart \
  test/features/groups/application/group_private_media_stale_library_boundary_test.dart \
  test/features/groups/application/group_received_media_action_policy_test.dart \
  test/features/groups/application/group_media_forward_policy_test.dart \
  test/features/groups/application/group_media_batch_actions_test.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart

flutter test \
  test/core/database/helpers/media_library_db_helpers_test.dart \
  test/features/groups/application/group_shared_media_repository_contract_test.dart \
  test/features/groups/presentation/group_shared_media_screen_test.dart

flutter test \
  test/core/database/helpers/group_messages_db_helpers_test.dart \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  test/features/orbit/application/load_orbit_groups_use_case_test.dart

flutter test \
  test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart \
  test/features/groups/integration/group_private_media_transport_boundary_test.dart \
  test/features/groups/integration/announcement_media_library_repository_test.dart
```

If an exact preservation filename does not yet exist, the RED-first test must
be created under the new names listed in scope before production.

### Registration, static, scope, and Graphify

```bash
./scripts/run_host_test_gates.sh feature-host-all --list
bash -n scripts/run_test_gates.sh
bash -n scripts/run_host_test_gates.sh
S01_DART_FILES=(
  lib/core/database/app_database_version.dart
  lib/core/database/production_migration_registry.dart
  lib/core/database/migrations/101_group_private_media_lifecycle.dart
  lib/core/database/helpers/media_library_db_helpers.dart
  lib/core/database/helpers/media_attachments_db_helpers.dart
  lib/core/database/helpers/group_messages_db_helpers.dart
  lib/core/bridge/bridge_group_helpers.dart
  lib/features/conversation/domain/repositories/media_attachment_repository.dart
  lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart
  lib/main.dart
  lib/features/groups/domain/models/group_private_media_policy.dart
  lib/features/groups/domain/models/group_message.dart
  lib/features/groups/domain/repositories/group_message_repository_impl.dart
  lib/features/groups/application/group_private_media_availability.dart
  lib/features/groups/application/send_group_message_use_case.dart
  lib/features/groups/application/retry_failed_group_messages_use_case.dart
  lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart
  lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart
  lib/features/groups/application/handle_incoming_group_message_use_case.dart
  lib/features/groups/application/group_message_listener.dart
  lib/features/groups/application/drain_group_offline_inbox_use_case.dart
  lib/features/groups/application/group_received_media_action_policy.dart
  lib/features/groups/application/group_received_media_actions.dart
  lib/features/groups/application/group_media_forward_policy.dart
  lib/features/groups/application/group_shared_media_library_controller.dart
  lib/features/groups/application/group_shared_media_batch_actions.dart
  lib/features/groups/presentation/screens/group_conversation_screen.dart
  lib/features/groups/presentation/screens/group_conversation_wired.dart
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart
  lib/features/groups/presentation/screens/group_list_screen.dart
  lib/features/feed/application/load_group_feed_snapshot_use_case.dart
  lib/features/feed/application/load_feed_use_case.dart
  lib/features/feed/domain/utils/group_group_messages_into_threads.dart
  lib/features/feed/presentation/screens/feed_wired.dart
  lib/features/orbit/application/load_orbit_groups_use_case.dart
  test/core/database/migrations/101_group_private_media_lifecycle_test.dart
  test/core/database/migrations/100_direct_private_media_lifecycle_test.dart
  test/core/database/integration/full_migration_chain_test.dart
  test/core/database/helpers/media_library_db_helpers_test.dart
  test/core/database/helpers/group_messages_db_helpers_test.dart
  test/core/bridge/bridge_group_helpers_test.dart
  test/core/lifecycle/main_resume_group_upload_wiring_test.dart
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart
  test/features/groups/domain/models/group_private_media_policy_test.dart
  test/features/groups/domain/models/group_message_test.dart
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart
  test/features/orbit/application/load_orbit_groups_use_case_test.dart
  test/features/groups/application/send_group_message_use_case_test.dart
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
  test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart
  test/features/groups/application/group_message_listener_test.dart
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
  test/features/groups/application/group_received_media_action_policy_test.dart
  test/features/groups/application/announcement_media_library_batch_actions_test.dart
  test/features/groups/shared_media_test_fakes.dart
  test/features/groups/application/group_media_forward_policy_test.dart
  test/features/groups/application/group_media_batch_actions_test.dart
  test/features/groups/application/group_shared_media_repository_contract_test.dart
  test/features/groups/application/group_private_media_safe_disabled_boundary_test.dart
  test/features/groups/application/group_private_media_retry_qualification_test.dart
  test/features/groups/application/group_private_media_preupload_boundary_test.dart
  test/features/groups/application/group_private_media_stale_library_boundary_test.dart
  test/features/groups/integration/group_private_media_payload_roundtrip_test.dart
  test/features/groups/integration/group_private_media_transport_boundary_test.dart
  test/features/groups/integration/announcement_media_library_repository_test.dart
  test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart
  test/features/groups/presentation/group_conversation_screen_test.dart
  test/features/groups/presentation/group_conversation_wired_test.dart
  test/features/groups/presentation/group_shared_media_screen_test.dart
  test/features/groups/presentation/group_shared_media_go_to_message_test.dart
  test/features/feed/presentation/screens/feed_wired_test.dart
  test/features/feed/application/load_group_feed_snapshot_use_case_test.dart
  test/features/feed/application/load_feed_use_case_test.dart
  test/features/feed/domain/utils/group_group_messages_into_threads_test.dart
  test/features/groups/presentation/group_list_screen_test.dart
  integration_test/group_recovery_cli_e2e_test.dart
)
dart format --output=none --set-exit-if-changed "${S01_DART_FILES[@]}"
for file in "${S01_DART_FILES[@]}"; do
  dart analyze "$file"
done
git diff --check
```

Do not invoke `./scripts/run_test_gates.sh`. The user explicitly directed this
continuation to skip it after running it elsewhere. The unrelated external
`groups` run that began before any Session-238-01 code is baseline-only and
cannot be represented as post-change evidence. Closure must state this
deviation exactly and must not invent a count/log. Final included-Wave-1
`host-all` remains pending and supplies the eventual aggregate host sweep.

After GREEN and before QA, run Graphify `affected` over every attributable
production file with budget 600. After independent QA accepts and all bounded
fixes are complete, run exactly one:

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Scope Guard

- Compare scoped before/after manifests; equality is required for every
  protected path not explicitly attributable to this session. Investigate
  concurrent movement and never revert it.
- Allowed Go delta is only the typed bridge parameter/option whitelist and its
  bridge tests. `go-mknoon/node`, libp2p, relay, group topic/auth/recipient/key,
  inbox protocol, and consumption-event behavior must remain unchanged.
- Android/iOS/native, direct private-media, announcement private behavior,
  Plans 242/243/248/254/241/253, and DB v100 bytes are protected.
- Same-ID direct/group/unresolved fixtures must prove only the exact group
  parent changes and no owner-lane inference from message ID.

## QA And Closure Contract

- Fresh independent QA reviews schema exactness, parser normalization,
  persisted-before-derivative ordering, every upload/fanout retry seam,
  production-off availability, SQL-before-`LIMIT`, encrypted-inner-only wire,
  ordinary/announcement/direct preservation, registration, scope, and the
  user-directed named-gate exception.
- Permit at most two bounded fix passes. Every behavioral fix requires a
  causal RED; docs-only corrections do not increment the implementation count.
- Persist `## Execution Result` only after QA accepts. Then run a separate
  read-only Closure Review, add `## Closure Audit`, update source/breakdown/
  index ledgers, and unblock only Session 238-02.
- No Session-238-02 code may land in a fix pass. Any consume/expiry/cleanup need
  found here is recorded as the already-owned next-session dependency, not
  silently implemented.

## Done Criteria

- [ ] Plan 234 remains accepted/closed and v100 bytes/registries are preserved.
- [ ] Source, breakdown, and index contain the accepted Plan-238 decisions,
      live entry points, and v101 ownership with no current unresolved/vNEXT
      wording; superseded pre-decision history is explicitly labeled.
- [ ] Every v101 column/type/default/check/index is exact, idempotent, and
      preserves v1–v100 plus same-ID owner collisions.
- [ ] Legacy absence is ordinary; every explicit invalid/unknown/inconsistent
      policy is durable typed unsupported and never ordinary.
- [ ] Only four sender policy fields traverse encrypted group extras; local
      timestamps/state never leave the device. Valid v1 preserves all four key
      presences, including explicit null duration, through Dart and Go.
- [ ] Current discussion authorization is rechecked before upload, dispatch,
      every send retry, incomplete-upload retry, and failed-inbox-store replay.
- [ ] Missing/empty/failed roster reads and absent/dissolved/non-chat groups deny
      private work; the ordinary permissive fallback is never reused.
- [ ] Initial and incomplete-retry upload occurs only after the exact
      policy-bearing parent is durably saved, reloaded, and requalified.
- [ ] Production availability remains off; early private/unsupported receipt
      has zero notification-content/download/decode/viewer/action/library leak.
- [ ] Group Shared Media excludes nonordinary/unsupported parents in SQL before
      keyset/`LIMIT`.
- [ ] Stale loaded-ordinary entries cannot bookmark, batch, clear, or egress a
      now-private/unsupported parent; exact bookmark mutation requalifies
      atomically without touching same-ID direct/unresolved siblings.
- [ ] Ordinary/legacy group, reaction, direct, same-ID sibling, and announcement
      behavior remains unchanged.
- [ ] All literal focused/Go/preservation/scope gates pass; scoped analyzer
      evidence has no Session-238-01 diagnostic relative to HEAD, and every
      baseline-only warning is reported rather than mislabeled as a pass. The
      skipped curated gate is recorded without an invented result.
- [ ] Graphify `affected`, fresh independent QA, bounded fix history, and exactly
      one post-QA incremental refresh pass.
- [ ] Separate Closure Review accepts with no residual/blocker/follow-up and
      only Session 238-02 is unblocked.

## Planning Review Result

- Initial independent review returned blockers B1–B5 and notes N1–N2. The plan
  now freezes the two-direction local lifecycle anchor, stale-library atomic
  mutation guard, durable pre-upload parent/requalification proof, strict
  roster-failure matrix, explicit-null wire presence, literal static commands,
  and corrected breakdown/exclusion ownership.
- Final independent re-review: `ACCEPTED`; no remaining blocker. SQLite
  in-memory execution also verified every proposed `ALTER TABLE` column CHECK,
  legacy default, and expiry index before RED.
- Historical planning verdict: `execution-ready`. Execution subsequently began
  only after unrelated test/writer processes settled and a fresh immutable
  scoped baseline was captured; current progress is recorded below.

## Execution Progress

- Execution began on 2026-07-12 only after the unrelated `core-host-all` and
  external pre-change `groups` gate finished. Neither external run is credited
  as Session-238-01 post-change evidence.
- Plan review accepted after B1–B5/N1–N2 corrections. The in-memory SQLite
  probe executed all ten proposed `ALTER TABLE` definitions, legacy defaults,
  and `idx_group_messages_private_media_expiry` successfully.
- Evidence root: `/tmp/plan238-s01.20260712`. The valid scoped baseline is
  `/tmp/plan238-s01.20260712/scoped.before`, SHA-256
  `1cbdb4fac440fc67770e68cf2f029a1295b561551a0e5c8f8d7138e831bca7e2`
  (`233,325` bytes). The whole dirty-status snapshot is SHA-256
  `06e009c32e30cfd5d24f08dfa5ff2cfef0c68f8f827cb0d73ffb3ec55cc88008`
  (`23,416` bytes). A prior attempted snapshot is invalid/no-credit because a
  zsh `path` loop variable shadowed `PATH`; it changed no repository file and
  was immediately replaced by this valid baseline.
- Foundation causal REDs were observed before production: GPL-01 exited 1 for
  the missing v101 migration/API; GPL-02 exited 1 for the missing policy type;
  the eligibility refinement exited 1 for missing group eligibility/kind/
  validation APIs.
- Foundation GREEN: named GPL-01 `1/1`, named GPL-02 `1/1`, migration plus
  full-chain `17/17`, and policy plus `GroupMessage` `15/15`. Per-file analysis
  over the nine foundation files and scoped `git diff --check` are clean.
  Landed scope is v101 version/registries/migration, strict group policy,
  `GroupMessage` mapping/copy, structural/full-chain/model tests. No wire,
  retry, action/library, presentation, native, device, or later-session code
  was included.
- The existing v100 preservation test truthfully failed its stale “current
  version is 100 / no successor” oracle after v101 landed. It is not a product
  regression; Session 238-01 updates it to keep v100 byte/runner ownership
  exact while asserting v101 is the sole sequential successor.
- The updated v100 preservation suite is GREEN `3/3`: v100 remains the exact
  successor of v99, v101 is the sole exact successor of v100, and a database
  opened at the v100 target still excludes every v101 group column even though
  the production registries now contain the sequential v101 runner.
- Before authorizing the two narrow `lib/main.dart` dependency wires, execution
  captured `/tmp/plan238-s01.20260712/main-wiring.before`, SHA-256
  `60160082249648e7cff229e2084851d82419f729ac28d354e990528ac0539085`
  (`43,785` bytes), plus the omitted resume-wiring sentinel as
  `/tmp/plan238-s01.20260712/main-resume-group-upload-wiring.before`, SHA-256
  `3dde6583963d52653eae2f9b8c3d2d6a8555915f5ac6aae12c85230be08e4b66`
  (`6,328` bytes). The separate action/library shield supplement is
  `/tmp/plan238-s01.20260712/shield-supplement.before`, SHA-256
  `7ae5fad1655b4dd7035a9bf5729d48e1bd397261766488722f5c669dff9ded8f`
  (`353` bytes). Current-source tracing, not the stale graph shortlist, proved
  the constructor/retry injection points load-bearing before any main edit.
- The first GPL-09B wiring-test attempt is no-credit because it encountered a
  concurrent intermediate send-slice compile error before reaching the new
  assertion. After that intermediate call site became compile-clean, the exact
  GPL-09B test exited 1 solely because `lib/main.dart` lacked
  `dbSetGroupMediaBookmarkedIfOrdinary`. Adding only the recorded constructor
  closure made the same named test GREEN `1/1`; no generic ID-only bookmark
  fallback was wired.
- With the retry seam compile-stable, GPL-03B exited 1 solely because both
  production `retryFailedGroupInboxStores` call sites omitted current group and
  identity authority. Wiring `groupRepo`/`identityRepo` at the background
  retrier and app-resume call sites made the same named test GREEN `1/1`.
- A read-only independent foundation counterexample review returned B1–B3.
  B1 showed that batched thread summary/preview maps omit v101 columns, causing
  `GroupMessage.fromMap` and Orbit to treat current private/unsupported latest
  rows as ordinary and request raw body/media derivatives. B2 showed partial
  wire tuples discard a valid nonnegative source version; B3 showed the public
  unsupported constructor can emit a negative version that violates the v101
  CHECK. Before any B1 edit, execution captured
  `/tmp/plan238-s01.20260712/orbit-projection-supplement.before.tar`, SHA-256
  `e620d4878c360ade1baff7d54c2496a77f4b2125993c84e5059a0b8131cff42d`
  (`162,816` bytes), and authorized only the exact projection/repository/Orbit
  seams and their three causal tests above.
- B1 also exposed that the conditional real-network CLI harness hard-coded a
  bespoke v90 create/upgrade chain and would call the now-v101 projection
  without its columns. Before fixture-only synchronization, execution captured
  `/tmp/plan238-s01.20260712/group-recovery-cli.before`, SHA-256
  `834f8f74b5f6f16bf612748958a7e61d2ab8bd75b995a031e845dcd32c1ccd1b`
  (`33,015` bytes). The intentionally bespoke group-recovery fixture is
  authorized only to advance its create/upgrade tail through the existing
  Plan-234 v100 runner and then the sequential v101 runner; it is not full-chain
  or SQLCipher migration evidence. Its conditional CLI/device journey is not
  converted into a Session-01 host gate or claimed as executed. The synchronized
  harness formats cleanly, has no analyzer issue, and passes scoped diff-check.
- B2/B3 received causal model REDs: partial
  `{mediaPolicyVersion: 7}` normalized to source version 0 instead of retaining
  7, and `unsupported(sourceVersion: -1)` emitted -1 instead of the required
  nonnegative 0. Deriving the sanitized version before tuple completeness and
  clamping the const constructor made exact GPL-02 GREEN `1/1`.
- B1 received four causal REDs before projection production changed: GPL-01B
  summary SQL omitted `latest_media_policy_version`; GPL-01C preview SQL did
  the same; GPL-01D both repository adapters hydrated a disappearing v1 row as
  ordinary v0; GPL-01E Orbit exposed unsupported raw text. Each exact test is
  GREEN `1/1`, and the post-fix helper/repository/Orbit batch is GREEN `93/93`
  (`28 + 54 + 11`). All six supplement files analyze and diff-check clean.
  Both batched paths now project/map all ten v101 fields, and Orbit suppresses
  private/unsupported body and descriptor loads while ordinary and fallback
  behavior remain unchanged.
- The safe-disabled shield slice preserved its two causal REDs before
  production: GPL-04A exited 1 for missing availability/policy action APIs and
  GPL-09A exited 1 for the missing exact atomic group bookmark capability.
  Both are GREEN `1/1`. Focused preservation is GREEN: SQL/repository/action/
  library/batch `53/53`, Forward `3/3`, and exact wired group-media viewer/
  action sentinels `4/4`. The earlier four-file presentation run is explicitly
  no-credit because its final output handle was lost. Per-file analysis and
  scoped format over the shield files are clean; screen/wired retain only
  pre-existing info lints with analyzer exit 0, and `git diff --check` is clean.
- GPL-15 then exposed a presentation bypass that the action-only shield did not
  cover: an availability-off View Once row still rendered its raw body and
  ordinary media grid. The named widget test exited 1 on the visible sentinel
  body before production. Redacting body, quote, media tiles, retry/context
  actions to the existing generic `Media unavailable` copy—while leaving the
  ordinary announcement row unchanged—made GPL-15 GREEN `1/1`.
- A causal GPL-04A listener case first persisted valid-private and unsupported
  parents but still emitted two notifications and began two downloads. The
  injected availability now defaults production-off and returns only after
  parent persistence/emission/key-repair, before attachment reload,
  notification body, or auto-download. The same test is GREEN `1/1`; its
  ordinary control still emits exactly one notification and one
  `media:download` call.
- GPL-03A initially lacked any initial-upload guard API. Its GREEN `1/1` now
  covers enabled writer, reader denial, durable-policy mismatch,
  production-disabled denial, and incomplete-upload retry. The actual wired
  send path pre-persists the policy/key-bearing parent, reloads and strictly
  requalifies it immediately around the upload callback, propagates policy to
  final send/retries, and rejects private upload on a non-durable path.
  GPL-03A-W is GREEN `1/1`: revoking the writer on private-parent save still
  caused a subsequent reload but zero upload/reliable/publish work. The exact
  ordinary durable-upload sentinel remains GREEN `1/1`.
- A further GPL-04A causal RED timed out after
  `GROUP_MESSAGE_LISTENER_EMPTY_DROP` discarded a partial version-7 tuple
  before persistence. Empty-body/media drop now applies only when all four
  policy keys are absent; GPL-04A is GREEN `1/1` with durable unsupported
  source version 7 and no derivatives.
- The scoped before/after comparison surfaced one load-bearing shield file
  that the original literal file list omitted:
  `group_received_media_actions.dart` performs the current-parent lifecycle
  refusal used by the already-recorded stale-action proof. Its two interface
  fixture adaptations are
  `announcement_media_library_batch_actions_test.dart` and
  `shared_media_test_fakes.dart`. This plan now names all three explicitly;
  their focused format and per-file analyzers pass with no issue, and the
  correction adds no Session-02 behavior. This is an exact reconstruction, not
  a contemporaneous pre-edit supplement: `status.before` shows all three clean
  at the valid baseline. Their HEAD-to-current blob hashes are respectively
  `faff8f8d16d7ac484a72a7f3b77a2632290b83f5` ->
  `f9dc4f250047ec7e576daeaa849e8376a0fd5fae`,
  `6a5e803fbb7a1027953166d631d87005b3d74384` ->
  `a27af750a43e0ce2815883dcf58b32e2e6ab1105`, and
  `435070749990e842a97829b0c277527635ca1bba` ->
  `18d86d305f28fd09e92d2947855c395194b35733`.
- Static execution is recorded as no-new-diagnostic parity, not blanket
  zero-exit. The first literal 63-file format check exited 1 and named twelve
  files: `production_migration_registry.dart`,
  `load_orbit_groups_use_case.dart`, the v100 preservation and full-chain
  tests, `group_messages_db_helpers_test.dart`,
  `main_resume_group_upload_wiring_test.dart`, the incomplete-upload and
  failed-inbox retry tests, incoming-handler and offline-drain tests,
  `group_received_media_action_policy_test.dart`, and
  `group_conversation_screen_test.dart`. Applying the formatter to those
  scoped files mechanically refolded pre-existing dirty text as well as the
  Session-01 additions; the controller accepts that scoped non-semantic
  widening explicitly and does not describe protected bytes or only
  Plan-238-authored lines as unchanged. The repeat 63-file check reports
  `0 changed`; the three-file scope supplement separately reports `0 changed`.
- Of the 66 per-file analyzer checks, 64 exited 0. The two exit-2 results are
  exact HEAD/baseline debt: `group_message_listener_test.dart:50:7` reports
  unused `_bytes123ContentHash`, and
  `drain_group_offline_inbox_use_case_test.dart:667:10` reports the never-
  supplied optional `delay`; neither declaration changed in this session.
  Four exit-0 files retain eleven pre-existing info diagnostics (`4+4+2+1`).
  No Session-238-01 diagnostic was introduced. Both script syntax checks and
  `git diff --check` pass. The host feature inventory dry-run passes with 765
  commands listed and zero tests executed.
- Graphify `affected` exited 0 across the original 29 attributable production
  files but truncated its 600-token display. The required focused refinement
  for `group_received_media_actions.dart` surfaced its direct action and
  Shared-Media Go-to consumer suites. The action suite passed both tests; the
  Go-to suite reached `4` passes before `GML-10R GML-13W` failed because its
  test fixture did not provide the newly required atomic group-bookmark
  repository, then finished `6/7`. That causal preservation gap and the fresh
  QA behavioral findings are assigned to bounded fix pass 1; no acceptance is
  claimed from this intermediate run.
- Execution deviation after the planned cap: fresh final counterexample QA
  rejected the result after two bounded passes on five still-causal Session-01
  bypasses: multi-entry/paged Shared Media viewer qualification, post-await
  Forward source qualification, post-await Info/library identity
  qualification, upload/retry parent replacement before dispatch, and
  Feed/Group List private derivatives. The user's repeated explicit direction
  to finish the rollout rather than stop controls this continuation. The
  controller therefore authorizes one exceptional third and final causal pass,
  limited to those five findings, with every production change still requiring
  a valid RED. This deviation will be reported as `fix_passes=3`; it is not
  relabeled as compliance with the original two-pass cap, and it authorizes no
  Session-02/native/relay/excluded-plan work.

## Execution Result

<!-- Intentionally empty until execution and fresh independent QA accept. -->
