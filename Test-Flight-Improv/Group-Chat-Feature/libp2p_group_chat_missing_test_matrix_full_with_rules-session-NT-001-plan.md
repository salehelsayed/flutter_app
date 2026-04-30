# NT-001 Session Plan - Push Bridge Is Encrypted Or Metadata-Minimized

Status: execution-safe local plan fallback for NT-001 only. The spawned planning
agent left only a scaffold; this fallback tightens the current-session contract
without executing code or tests.

## Scope

Current session only: `NT-001`, "Push bridge is encrypted or
metadata-minimized." Prove or repair the push-visible payload and fallback
notification behavior for group text, media, mention-compatible, and
announcement-style group pushes. Keep this row separate from NT-006 notification
dedupe and from the broader OS-state device-lab matrix in NT-007.

## Source Of Truth

- Breakdown artifact:
  `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix row:
  `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- Coverage inventory:
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Current row status at planning time: `Partial`
- Active mode: `standard`; degraded local continuation is not allowed.

## Dependency State

No session dependency. The worktree is intentionally dirty from prior sessions;
record `git status --short` before execution and classify only NT-001 deltas.
Do not revert user or prior-session changes.

## Exact Problem Statement

The matrix says push routing exists, but the privacy-minimized payload matrix is
incomplete. Current code has encrypted preview support in
`push_decrypt_preview.dart` and fixture rules saying push-visible `routeData`
must not contain sender display names, group names, message text, or media
descriptors, while `background_push_notification_fallback.dart` still accepts
generic `title` and `body` data. Execution must determine whether this is
acceptable metadata, a legacy compatibility path, or an NT-001 privacy gap.

## Likely Code Entry Files

- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/set_group_muted_use_case.dart`
- `test/features/push/fixtures/*.json`
- `test/features/push/fixtures/README.md`

## Likely Direct Tests

- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/push_decrypt_preview_test.dart`
- `test/features/push/application/push_preview_telemetry_gate_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `test/features/groups/application/set_group_muted_use_case_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`

## Execution Plan

1. Evidence pass: inspect push fixtures, route-target parsing, fallback
   materialization, decrypt-preview handling, group mute/privacy tests, and
   group listener notification construction. Record whether push-visible maps
   carry only route metadata plus encrypted envelope fields, or whether they can
   expose plaintext sender, group, message, media, mention, or announcement
   content before local decrypt or local policy checks.
2. If current repo evidence proves NT-001 fully covered, add no code; run the
   focused tests below and update the source matrix plus `test-inventory.md` to
   `Covered` with exact file-and-command evidence.
3. If code or tests are missing, implement only the minimum NT-001 gap. Likely
   acceptable repairs include rejecting or ignoring plaintext preview aliases in
   push-visible data, adding fixture canary checks for forbidden fields, and
   adding focused tests that hidden sender/content/group/media settings do not
   leak through fallback or route data. Do not broaden into full notification
   preferences, read receipts, delivery receipts, or dedupe.
4. If proof requires a raw APNs/FCM/relay capture or OS/device-lab harness not
   available in repo, keep the source row `Partial`, record a blocker class, and
   preserve any passed host evidence as adjacent evidence only.

## Tests And Gates

Run the narrowest passing set that proves the final NT-001 decision:

- `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart`
- `flutter test --no-pub test/features/push/application/push_decrypt_preview_test.dart`
- `flutter test --no-pub test/features/push/application/push_preview_telemetry_gate_test.dart`
- `flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/set_group_muted_use_case_test.dart`
- `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`
- `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` when foreground push drain coverage is needed on this host.
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

If a Flutter device or real-network relay gate is needed, prefix the command
inline with:

`FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly`

## Done Criteria

- The execution result states whether NT-001 is `accepted`, `blocked`, or still
  execution-incomplete.
- If accepted, the source matrix row and `test-inventory.md` record NT-001 as
  `Covered` with concrete code/test evidence.
- If blocked, both docs keep NT-001 `Partial` and name the exact blocker class,
  such as `missing_raw_push_payload_capture_proof` or
  `missing_push_privacy_policy_surface`.
- This plan records all commands actually run and their results.
- The breakdown ledger and NT-001 closure ledger are updated by closure.

## Scope Guard

Do not implement NT-002 preference variants, NT-006 dedupe, NT-007 OS-state
matrix coverage, read/delivery receipts, broad notification UI redesigns, or
new relay protocol architecture unless the NT-001 evidence directly proves a
minimal privacy leak in a shared helper that must be fixed to close this row.

## Known Failure Interpretation

- Tests proving encrypted local decrypt previews may pass while NT-001 remains
  `Partial` if raw push-visible payloads can still contain plaintext preview
  fields or if hidden sender/content/group settings are not enforced.
- A configured real-network gate passing self-contained scenarios is not enough
  for raw push payload privacy unless the output includes actual push payload or
  equivalent fixture/capture proof.
- Existing tests that intentionally pass `title`/`body` through fallback must be
  classified: legacy compatibility, allowed generic metadata, or privacy gap.

## Execution Result - 2026-04-30

Final execution verdict: `accepted`.

Spawned-agent isolation: attempted. The spawned execution child no-progressed
without NT-001 artifact or scoped diff changes under bounded wait, so the
pipeline used its single local execution fallback for this session.

Pre-execution dirty worktree snapshot: the tree already contained broad
prior-session modifications across the breakdown, source matrix, inventory,
Go node files, group/media/feed Flutter files, and many untracked prior-session
plan/migration/model/test files. Current-session deltas are limited to:

- `lib/features/push/application/background_push_notification_fallback.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/push_decrypt_preview_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-NT-001-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Implementation summary:

- `background_push_notification_fallback.dart` now treats data-only
  `new_message` and `group_message` pushes as protected preview paths. It
  ignores push-visible `title` and `body` and uses generic fallback copy until
  local decrypt resolves a preview.
- Visible `RemoteMessage.notification` payloads still suppress local fallback.
- Non-message fallbacks, including intros, contact requests, group invites, and
  post routes, retain their explicit copy path.
- `push_decrypt_preview_test.dart` now scans current push fixtures and
  post-phase1 frozen payload route data for forbidden plaintext preview keys:
  `title`, `body`, `pushTitle`, `pushBody`, `senderUsername`, `groupName`,
  `messageText`, `text`, and `media`.

Tests and gates run:

- `dart format lib/features/push/application/background_push_notification_fallback.dart test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/push_decrypt_preview_test.dart` - passed.
- `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/push_decrypt_preview_test.dart test/features/push/application/push_preview_telemetry_gate_test.dart` - passed after correcting test expectations in the local executor pass.
- `flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/features/groups/application/set_group_muted_use_case_test.dart test/integration/group_notification_dedupe_integration_test.dart` - passed.
- `./scripts/run_test_gates.sh completeness-check` - passed with `694/694 test files classified`.
- `git diff --check` - passed.

QA review:

- Scope adherence: pass. The diff touches only push fallback privacy, focused
  push tests, and NT-001 docs.
- Behavior correctness: pass. Protected chat/group data-only fallback no longer
  trusts plaintext data fields, while local decrypt previews still materialize
  decrypted sender/body text on device.
- Missing required tests/gates: none for this repo-local NT-001 closure. The
  optional foreground device integration command was not needed because the
  changed path is background fallback/push fixture privacy, and the focused
  foreground route/open/dedupe tests passed.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none for NT-001.

Docs updated during execution:

- Source matrix NT-001 row marked `Covered` with concrete code/test evidence.
- `test-inventory.md` now records NT-001 as `Covered` with focused evidence.
