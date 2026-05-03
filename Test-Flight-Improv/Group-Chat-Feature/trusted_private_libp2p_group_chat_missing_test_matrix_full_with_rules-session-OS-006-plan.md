# Session OS-006 Plan - Partial History, Gap Detection, and Multi-Peer Gap Repair

Status: prerequisite-blocked

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `OS-006` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: move OS-006 to `Covered` only if the repo has concrete partial-history detection, durable missing-range or gap lifecycle state, repair from multiple authorized peers or equivalent multi-source history providers, duplicate-safe ordering, and UI truth for partial or repaired history.
- Source status at intake: `Open`.

## Evidence Intake

Current repo behavior:

- `drain_group_offline_inbox_use_case.dart` drains group relay inbox pages through `group:inboxRetrieveCursor`, continues with opaque cursors instead of timestamp guessing, and can stop after the first page while reporting incomplete continuation telemetry.
- Cursor timeout/errors are emitted as group drain errors instead of silently treating backlog as drained.
- Old backlog outside the retention window is skipped while later retained cursor pages still continue; the group records retained and expired backlog timestamps.
- Message-id dedupe prevents duplicate rows when the same replay appears on multiple cursor pages or through live plus inbox delivery.
- `group_resume_recovery_test.dart` proves fake-network partition recovery through relay-stored cursor pages preserves order and resumes live delivery after heal.
- `group_backlog_retention_notice.dart`, `group_conversation_screen.dart`, and `group_list_screen.dart` show partial-history truth for expired and mixed-window backlog.
- Go node/bridge tests prove cursor defaults, opaque cursor forwarding, no duplicate continuation pages, bridge command exposure, second-relay cursor fallback, watchdog restart namespace recovery, and warm retry after partial initial recovery.

Known current gap:

- There is no first-class direct peer history repair protocol or app/Go command for history ranges, known heads, hash chains, missing range claims, or authorized peer-supplied history.
- There is no durable gap marker, repair lifecycle, anti-entropy owner, multi-peer source selection, repair clearance proof, or UI state that distinguishes "gap detected and actively repaired" from "retention-window backlog expired".
- The existing evidence is relay inbox cursor recovery and retention honesty, not multi-peer gap repair.

## Scope Guard

Do not mark OS-006 `Covered` from single relay inbox replay, fake-network cursor replay, or retention banners alone. Closure requires real multi-peer or equivalent multi-source gap repair primitives and tests.

## Direct Evidence

Passed commands:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'resume uses cursor continuation rather than timestamp guessing'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'cursor timeout logs a group error instead of treating backlog as drained'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'first group inbox page returns before background continuation completes'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'mixed old and new cursor pages keep retained backlog and record both boundaries'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'multi page backlog uses cursor continuation without duplication'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'long-offline mixed-window recovery keeps retained backlog and never resurrects expired pages'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'temporary partition replays missed backlog in cursor order and resumes live delivery after heal'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'backlog'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'shows mixed-window retention banner while retained messages stay visible'`
- `flutter test --no-pub test/features/groups/presentation/group_list_screen_test.dart --plain-name 'backlog summary'`
- `cd go-mknoon && go test ./node ./bridge -run 'TestGroupInboxRetrieveCursor_(StableAcrossPages|NoDuplicateOnContinuation|DefaultsLimitWhenZero|RequiresStartedNode|NegativeLimitDefaultsTo50|PassesOpaqueCursor|CommandExposed)|TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace|TestGroupInboxRetrieveWithCursor_TriesSecondRelayWhenFirstFails' -v`
- `git diff --check`

## Blocker

- Blocker classes:
  - `missing_multi_peer_gap_repair_primitives`
  - `missing_direct_peer_history_repair_protocol`
  - `missing_partial_history_gap_marker_and_repair_lifecycle`
  - `missing_gap_repair_clearance_proof`
- OS-006 moves from `Open` to `Partial` only to record concrete relay cursor, retention-honesty, and fake-network partition replay evidence. It remains prerequisite-blocked because multi-peer gap repair is not implemented or testable as a first-class production surface.
