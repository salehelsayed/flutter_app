# Group Chat Feature -- Test Inventory

**Date:** 2026-04-29
**Scope:** All automated tests covering the Group Chat feature across unit, widget, integration, cross-feature, E2E, Go-side categories, the Report 85 group-onboarding/crypto coverage addendum, and the Report 90 GMAR-005 closure addendum.

---

## How to Run

**Full host-side group suite:**

```sh
flutter test --no-pub test/features/groups
```

**Database helpers only:**

```sh
flutter test --no-pub \
  test/core/database/helpers/groups_db_helpers_test.dart \
  test/core/database/helpers/group_messages_db_helpers_test.dart \
  test/core/database/helpers/group_messages_db_helpers_sending_test.dart \
  test/core/database/helpers/group_messages_db_helpers_reliability_test.dart \
  test/core/database/helpers/group_members_db_helpers_test.dart \
  test/core/database/helpers/group_keys_db_helpers_test.dart \
  test/core/database/helpers/group_event_log_db_helpers_test.dart
```

**Background task protection only:**

```sh
flutter test --no-pub \
  test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

**Lifecycle recovery only:**

```sh
flutter test --no-pub \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart \
  test/core/lifecycle/main_resume_group_upload_wiring_test.dart
```

**Integration smoke tests only:**

```sh
flutter test --no-pub test/features/groups/integration
```

**Report 85 focused host/app-layer suites:**

```sh
flutter test --no-pub \
  test/features/groups/integration/group_new_member_onboarding_test.dart \
  test/features/groups/integration/announcement_new_reader_onboarding_test.dart \
  test/features/groups/integration/group_media_fanout_test.dart \
  test/integration/routing_smoke_group_criteria_test.dart
```

**PREREQ-GM multi-party harness criteria only:**

```sh
flutter test test/integration/group_multi_party_device_criteria_test.dart
```

**E2E device tests (requires running simulator):**

```sh
flutter test integration_test/group_recovery_e2e_test.dart
flutter test integration_test/group_recovery_cli_e2e_test.dart
flutter test integration_test/group_real_crypto_onboarding_test.dart -d <device>
flutter test integration_test/foreground_group_push_drain_test.dart -d <device>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de002 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de003 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de007 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de017 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir001 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl002 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d <alice>,<bob>,<charlie>,<dana>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm003 -d <alice>,<bob>,<charlie>,<dana>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge006 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge007 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge008 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge009 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge010 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge011 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge012 -d <alice>,<bob-primary>,<bob-sibling>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge013 -d <alice>,<bob-primary>,<bob-sibling>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge016 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge021 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge023 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge024 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario go001 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario go002 -d <alice>,<bob>,<charlie>
MKNOON_RELAY_ADDRESSES=<exact required relay list> \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario go003 -d <alice>,<bob>,<charlie>
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> \
  ./scripts/run_test_gates.sh group-real-network-nightly
```

The multi-party harness criteria binds receiver `messageId`, text/plaintext, `senderPeerId`, `timestamp`, and `keyEpoch` to the sender `sentMessages` tuple. Row-specific sessions consume it with direct scenario commands such as `gm001`, `de002`, `de003`, `de007`, `de017`, `ir001`, `pl002`, `gm002`, `gm003`, `ge006`, `ge007`, `ge008`, `ge009`, `ge010`, `ge011`, `ge012`, `ge013`, `ge016`, `ge021`, `ge023`, `go001`, `go002`, and `go003`; `gm001` also carries the DE-001 `de001LiveDeliveryProof` over the real A/B/C harness, `de002` carries the DE-002 rapid ordered-delivery proof over the same real A/B/C harness, `de003` carries the DE-003 stable message-id proof, `de007` carries the DE-007 zero-peer durable replay proof, `de017` carries the DE-017 membership-ordering proof, `ir001` carries the IR-001 offline active reconnect proof, and `pl002` carries the PL-002 media-only empty-text proof.

**Go-side group tests:**

```sh
cd go-mknoon && go test ./crypto/ ./internal/ ./node/ ./bridge/ ./cmd/testpeer/ -run 'Group|Announcement|Watchdog.*Group' -v
```

---

## Summary (2026-04-29 Tracked Inventory)

### Dart Tests

| Category | Files | Test Cases |
|----------|------:|-----------:|
| Domain (models, repo impl) | 14 | 107 |
| Data (DB helpers) | 7 | 88 |
| Data (DB migrations) | 13 | 40 |
| Application (use cases, listeners) | 37 | 451 |
| Presentation (widgets, screens) | 20 | 258 |
| Integration (smoke, round-trip, recovery) | 9 | 133 |
| Core (lifecycle, bridge) | 6 | 82 |
| Cross-feature (feed, orbit, push, intro, share, resilience, services, notifications, host criteria) | 32 | 206 |
| Test helpers & fakes | 1 | 2 |
| E2E / Device (`integration_test/`) | 2 | 5 |
| **Dart Total** | **141** | **1372** |

### Go Tests

| Category | Files | Group-Related Tests |
|----------|------:|--------------------:|
| Crypto (`crypto/`) | 1 | 14 |
| Envelope / Wire Format (`internal/`) | 1 | 11 |
| PubSub Core (`node/pubsub*.go`) | 4 | 123 |
| Shared Security Harness (`node/group_security_harness_test.go`) | 1 | 1 |
| Group Inbox (`node/group_inbox*.go`) | 1 | 15 |
| Multi-Relay (`node/multi_relay*.go`) | 1 | 3 |
| Rendezvous (`node/rendezvous*.go`) | 1 | 2 |
| Config (`node/config*.go`) | 1 | 1 |
| Protocol Version (`node/protocol_version_test.go`) | 1 | 4 |
| Node / Relay Session / Stream (`node/node*.go`, `node/relay_session*.go`, `node/stream_timeout*.go`) | 3 | 18 |
| Bridge API (`bridge/`) | 2 | 57 |
| CLI Test Peer (`cmd/testpeer/`) | 1 | 4 |
| Integration (`integration/`) | 2 | 3 |
| **Go Total** | **20** | **256** |

### Grand Total

| | Files | Tests |
|-|------:|------:|
| **All (Dart + Go)** | **161** | **1628** |

> **Note:** Dart file counts reflect distinct `_test.dart` files. Some inventory sections cover multiple files (e.g., 4.9 covers `archive_group_use_case_test.dart` + `unarchive_group_use_case_test.dart`; 4.30 covers three reaction test files). Dart test counts are `grep`-verified against `test()`/`testWidgets()` declarations in each file. Cross-feature test counts include only the group-relevant subset from shared test files. Go test counts reflect only group-related `func Test*` functions in files that may also contain non-group tests; counts are `grep`-verified against `func Test.*[Gg]roup` patterns and manual review for files with indirect group test names. Aggregate totals reflect the tracked 2026-04-29 inventory updates plus row closure notes below; DB-002 closure evidence is recorded in the crosswalk, and aggregate totals were not fully recounted during that row closure. Report 90 GMAR-005 closure on 2026-05-03 adds final acceptance evidence without a full aggregate recount: direct GMAR suites, configured simulator media proofs, paired simulator routing/group and foreground group push smoke commands, device-pinned `all`, `completeness-check` (`712/712`), broad `flutter test`, `cd go-mknoon && go test ./...`, and `git diff --check` all passed. GIS-001 closure on 2026-05-07 adds row-level invite-status coverage below without a full aggregate recount; the accepted gate evidence classified `730/730` test files. GEK-001 closure on 2026-05-09 adds direct listener/Go-boundary epoch-key monotonicity evidence below without a full aggregate recount. GEK-002 closure on 2026-05-09 adds host app-layer live decrypt durable-repair evidence below without a full aggregate recount; its old fixed-date receipt-fixture follow-up was closed during GEK-005 recovery. GEK-003 closure on 2026-05-09 adds host app-layer partial key-update rotation/send/repair evidence below without a full aggregate recount. GEK-005 recovery on 2026-05-10 adds final Report 94 residual-only evidence without a full aggregate recount. GM-002 blocked closure on 2026-05-10 adds host/config inventory entries below without a full aggregate recount; GM-002 remains Open until exact A/B/C/D or equivalent multi-party Flutter-app `3-Party E2E` proof runs. GO-008 and GO-009 closures on 2026-05-13 add row-level privacy/race evidence below without a full aggregate recount. GO-012 closure on 2026-05-13 adds one fake-helper Dart test file with two exact GO-012 tests and updates the aggregate counts by +1 file/+2 tests for that row. GL-010, GL-016, and GL-020 closures on 2026-05-13 add three Go PubSub Core tests and update the aggregate counts by +3 tests for those rows. GM-032 closure on 2026-05-13 adds three Dart application tests across existing files and updates the aggregate counts by +3 tests. GK-028 closure on 2026-05-13 adds one Dart application test and two Go PubSub Core tests across existing files, updating aggregate counts by +3 tests. GK-031 closure on 2026-05-13 adds two Go PubSub Core tests across existing files, updating aggregate counts by +2 tests. GK-032 closure on 2026-05-13 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GA-018 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GA-026 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-007 closure on 2026-05-14 adds one Dart application test, one Dart integration test, and one Go PubSub Core test across existing files, updating aggregate counts by +3 tests. GP-009 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-012 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-013 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-017 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-018 closure on 2026-05-14 adds one Go PubSub Core test in an existing file plus narrow Go cadence-helper extraction, updating aggregate counts by +1 test. GP-019 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-020 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GP-024 closure on 2026-05-14 adds one Go PubSub Core test in an existing file plus a narrow native subscription-error classifier, updating aggregate counts by +1 test. GP-027 closure on 2026-05-14 adds one Dart presentation widget test in an existing file, updating aggregate counts by +1 test. GI-008 closure on 2026-05-14 adds one Go Group Inbox test in an existing file, updating aggregate counts by +1 test. GI-010 closure on 2026-05-14 adds one Go Group Inbox test in an existing file, updating aggregate counts by +1 test. GI-028 closure on 2026-05-14 adds one Go Group Inbox test in an existing file, updating aggregate counts by +1 test. GI-030 closure on 2026-05-14 adds one Go Group Inbox test in an existing file, updating aggregate counts by +1 test. GI-034 closure on 2026-05-14 adds one Dart application test in an existing file, updating aggregate counts by +1 test. GR-001 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-002 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-003 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-007 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-009 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-010 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-011 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-012 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-013 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-018 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GR-019 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GR-020 closure on 2026-05-14 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. GE-016 closure on 2026-05-14 adds one Dart integration smoke test plus two criteria tests across existing files, updating aggregate counts by +3 tests. GE-021 closure on 2026-05-14 adds one Dart integration smoke test plus two criteria tests across existing files, updating aggregate counts by +3 tests. GE-023 closure on 2026-05-14 adds one Dart integration smoke test plus two criteria tests across existing files, updating aggregate counts by +3 tests. GE-024 closure on 2026-05-14 adds one Dart presentation widget test, one Dart integration smoke test, and two criteria tests across existing files, updating aggregate counts by +4 tests. GO-005 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GO-006 closure on 2026-05-14 adds one Go PubSub Core test in an existing file, updating aggregate counts by +1 test. GO-007 closure on 2026-05-14 adds one Go PubSub Delivery test in an existing file, updating aggregate counts by +1 test. GO-010 closure on 2026-05-14 adds one Go PubSub Core lifecycle/leak test in an existing file, updating aggregate counts by +1 test. DE-010 closure during worktree-to-main integration on 2026-05-18 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. DE-011 closure during worktree-to-main integration on 2026-05-18 adds one Go Node / Relay Session test in an existing file, updating aggregate counts by +1 test. DE-012 closure during worktree-to-main integration on 2026-05-18 adds one Dart application listener test, one Dart fake-network integration test, and one Go Node / Relay Session test across existing files, updating aggregate counts by +3 tests. DE-013 closure during worktree-to-main integration on 2026-05-18 adds one Dart application listener test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. DE-014 closure during worktree-to-main integration on 2026-05-18 adds one Dart application listener test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. DE-015 closure during worktree-to-main integration on 2026-05-18 renames/extends one existing Dart bridge diagnostic test and adds one Dart fake-network integration test across existing files, updating aggregate counts by +1 test. DE-016 closure during worktree-to-main integration on 2026-05-19 renames/extends one existing Dart bridge diagnostic test and adds one Dart fake-network integration test across existing files, updating aggregate counts by +1 test.

> **DE-017 note:** DE-017 closure during worktree-to-main integration on 2026-05-19 adds one Dart domain model test, two Dart listener tests, one Dart fake-network integration test, and three multi-party criteria tests across existing files, updating aggregate counts by +7 tests.

> **DE-018 note:** DE-018 closure during worktree-to-main integration on 2026-05-19 adds one Dart bridge-router unit test in an existing file, updating aggregate counts by +1 test.

> **DE-019 note:** DE-019 closure during worktree-to-main integration on 2026-05-19 adds two Dart bridge EventChannel recovery unit tests in an existing file, updating aggregate counts by +2 tests.

> **DE-020 note:** DE-020 closure during worktree-to-main integration on 2026-05-19 adds one Go native dispatcher test, one Dart bridge callback test, and one Dart fake-network integration test across existing files, updating aggregate counts by +3 tests.

> **RA-011 note:** RA-011 worktree-to-main integration on 2026-05-19 adds the late self-removal leave repair path, deterministic delayed leave hook, one Dart listener test, one Dart fake-network integration test, and three multi-party criteria tests across existing files. The live harness/runner/criteria now expose `private_late_leave_readd` with `ra011LateLeaveReaddProof` for controller-owned device proof.

> **IR-001 note:** IR-001 closure during worktree-to-main integration on 2026-05-19 adds four multi-party device criteria tests in an existing host criteria file, updating aggregate counts by +4 tests. The source fake-network selector was skipped as already present because current main's partition-heal replay selector proves equivalent or stronger behavior.

> **IR-002 note:** IR-002 closure during worktree-to-main integration on 2026-05-19 adds one Dart core bridge test and one Dart application drain test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; the row imported only the missing cursor metadata parser proof and restart-between-pages durable cursor drain proof.

> **IR-003 note:** IR-003 closure during worktree-to-main integration on 2026-05-19 adds one Go native group inbox test, one Dart application drain test, and one Dart fake-network integration test across existing files, updating aggregate counts by +3 tests. The only imported production delta is the direct legacy native timestamp retrieve using the existing inclusive boundary helper; Dart synthetic cursor behavior was already present.

> **IR-004 note:** IR-004 closure during worktree-to-main integration on 2026-05-19 adds one Dart application drain test and two net Dart criteria tests across existing files, updating aggregate counts by +3 tests. Production code stayed untouched; current main already had the recipient entitlement skip behavior and removal-cutoff coverage, so the row imported only the missing row-owned skip-before-decrypt proof and `private_offline_remove` criteria/live-harness evidence.

> **IR-005 note:** IR-005 closure during worktree-to-main integration on 2026-05-19 renames/extends existing KE-018 direct-drain and GM-007 fake-network selectors, adds two net Dart criteria tests across existing files, and imports `gm007` live-harness/runner proof fields, updating aggregate counts by +2 tests. Production code stayed untouched; current main already had the re-added member replay-window behavior, so the row imported only the missing row-owned decrypt-attempt assertion, IR-005 row identity, criteria validation/tests, stale-app runner guard, and iOS 26.2 `gm007` proof evidence.

> **IR-006 note:** IR-006 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test in an existing file and renames/extends one existing fake-network KE-021 selector, updating aggregate counts by +1 test. Production code stayed untouched; current main already had equal or stronger active-recipient computation through send-time membership cutoff, deliverable identity filtering, sender exclusion, and recipient dedupe, so the row imported only the missing row-owned direct and fake-network proof artifacts.

> **IR-007 note:** IR-007 closure during worktree-to-main integration on 2026-05-19 adds three Dart application tests across existing files and renames/extends two existing fake-network retry-ownership selectors, updating aggregate counts by +3 tests. Production code stayed untouched; current main already had the retry ownership behavior through pending inbox-store retry and failed-message retry paths, so the row imported only missing row-owned direct, retry-use-case, and fake-network proof artifacts.

> **IR-008 note:** IR-008 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already had retrieve-before-commit cursor/ack behavior, so the row imported only missing row-owned direct and fake-network proof artifacts.

> **IR-009 note:** IR-009 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already had process-before-commit cursor/ack behavior, so the row imported only missing row-owned local-persistence-failure direct and fake-network proof artifacts.

> **IR-010 note:** IR-010 closure during worktree-to-main integration on 2026-05-19 adds one Dart core bridge test and one Dart application test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already had cursor history-gap parsing and drain-side repair lifecycle behavior, so the row imported only missing row-owned parser and drain lifecycle proof artifacts.

> **IR-011 note:** IR-011 closure during worktree-to-main integration on 2026-05-19 adds one Go Group Inbox test, one Dart core bridge test, one Dart application test, and one Dart fake-network integration test across existing files, updating aggregate counts by +4 tests. Production code stayed untouched; current main already had repair request normalization, invalid-input surfacing, and drain-side wrong group/gap/source validation, so the row imported only missing row-owned native, bridge, drain, and fake-network proof artifacts.

> **IR-012 note:** IR-012 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already validates repair `headMessageId`, response `rangeHash`, and computed range hash before applying repaired history, so the row imported only missing row-owned direct and fake-network hash/head fallback proof artifacts.

> **IR-013 note:** IR-013 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already records unauthorized repair candidates without requesting them, validates returned repair `sourcePeerId` before applying repaired history, and falls back to later authorized sources, so the row imported only missing row-owned direct and fake-network unauthorized-source injection proof artifacts.

> **IR-014 note:** IR-014 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production code stayed untouched; current main already stores relay-visible replay as an opaque `group_offline_replay` envelope and omits retired native push preview fields, so the row imported only missing row-owned direct and fake-network relay-opacity proof artifacts. The native Go source selector body was skipped as already present through `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope`.

> **IR-015 note:** IR-015 closure during worktree-to-main integration on 2026-05-19 adds one Dart application replay test, one Dart fake-network integration test, and three multi-party device criteria tests across existing files, updating aggregate counts by +5 tests. `application/octet-stream` is now pinned as a safe generic file MIME for group replay while dangerous/unsupported MIME values remain rejected. The row imported only missing row-owned direct, fake-network, criteria, runner, and iOS 26.2 live-harness proof artifacts for text, quote, image, video, file, GIF, and voice replay variants.

> **IR-016 note:** IR-016 closure during worktree-to-main integration on 2026-05-19 adds one Dart application replay-retention test and three multi-party device criteria tests across existing files, updating aggregate counts by +4 tests. Existing fake-network and UI retention selectors were row-named/strengthened without increasing counts. Production retention behavior was already present, so the row imported only missing row-owned direct, fake-network, UI, criteria, runner, and iOS 26.2 live-harness proof artifacts for explicit long-offline cutoff state and retained-backlog visibility.

> **IR-017 note:** IR-017 closure during worktree-to-main integration on 2026-05-19 adds one Dart listener test and one Dart fake-network integration test across existing files, updating aggregate counts by +2 tests. Production and native dispatcher-overflow recovery behavior was already present through DE-012, so the row imported only missing row-owned proof that dispatcher-overflow diagnostics name replay recovery as the reason, restore the dropped inbox replay exactly once, and remain deduped across repeat overflow-triggered drains.

> **IR-018 note:** IR-018 closure during worktree-to-main integration on 2026-05-19 adds three Dart presentation widget tests, one Dart lifecycle test, and one Dart fake-network startup integration test across existing files, updating aggregate counts by +5 tests. The row imports the observable recovery-depth gate, wired recovery listener, recovering banner/loading-state UI, and host-only proof that restart recovery keeps the UI visibly catching up until replay drain completes while live messages still arrive.

> **RA-001 note:** RA-001 closure during worktree-to-main integration on 2026-05-19 imported no code, test, criteria, script, harness, fixture, or helper deltas because current main already has equivalent/stronger coverage through COMPLETE_1 GM-007 history-boundary proof, GM-006 post-readd bidirectional/future delivery proof, and current IR-005 `gm007` proof evidence. Counts are unchanged. Evidence passed: GM-006 host selector (`+1`), GM-007/IR-005/KE-018 host selector (`+1`), GM-006 criteria selector (`+5`), GM-007 criteria selector (`+8`), and scoped analyzer (`No issues found!`).

> **RA-002 note:** RA-002 closure during worktree-to-main integration on 2026-05-19 adds one Dart fake-network integration test and two multi-party criteria tests across existing files, updating aggregate counts by +3 tests. Production code stayed untouched. The row imported only missing row-owned proof surfaces for the online/subscribed removed-member re-add path: the RA-002 host selector, `ra002OnlineSubscribedReaddProof` live-harness verdict fields, criteria validation, fixture fields, and missing/leak negative criteria coverage. Evidence passed: focused RA-002 host selector (`+1`), focused `private_readd_current` criteria selector (`+15`), affected GM-016/GM-017/GM-018/GM-019/GM-024/IR-005 preservation selectors, scoped analyzer (`No issues found!`), iOS 26.2 `private_readd_current` live proof run `1779181396891` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_dPRI1j`. Broad `groups` remains red only on preserved non-RA-002 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).

> **RA-016 note:** RA-016 worktree-to-main integration on 2026-05-19 adds one direct drain selector, one fake-network selector, `private_readd_current` `ra016RemovedIntervalReplayProof` criteria/harness fields, and six focused criteria tests. Production code stayed untouched because current main already rejects removed-interval replay after re-add; the tests accept either current diagnostic split while proving the removed-window message is not persisted and post-readd current delivery remains converged.

> **RA-003 note:** RA-003 closure during worktree-to-main integration on 2026-05-19 adds one Dart fake-network integration test and two multi-party criteria tests across existing files, updating aggregate counts by +3 tests. Production code stayed untouched. The row imported only missing row-owned proof surfaces for the offline-removed/online-readded member path: the RA-003 host selector, `private_offline_readd` runner and live-harness routing, `ra003OfflineReaddProof` verdict fields, criteria validation, fixture fields, and missing/leak negative criteria coverage. Evidence passed: focused RA-003 host selector (`+1`), focused `offline_readd` criteria selector (`+3`), GE-006 and affected GM-016/GM-017/GM-018/GM-019/GM-024/IR-005/RA-002 preservation selectors, scoped analyzer (`No issues found!`), and iOS 26.2 `private_offline_readd` live proof run `1779184279659` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_readd_l6RN7b`. Broad `groups` remains red only on preserved non-RA-003 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).

> **RA-004 note:** RA-004 closure during worktree-to-main integration on 2026-05-19 adds one Dart application test, one Dart fake-network integration test, and three multi-party criteria tests across existing files, updating aggregate counts by +5 tests. Production code stayed untouched. The row imported only missing row-owned proof surfaces for stale old-invite acceptance before current re-add: the RA-004 application selector, fake-P2P round-trip selector, `ra004StaleInviteBeforeReaddProof` criteria validation, positive/missing/old-accept-success criteria cases, and old-accept-before-current coordination plus proof fields in the existing `private_stale_invite_readd` live harness path. Evidence passed: focused RA-004 application selector (`+1`), focused RA-004 round-trip selector (`+1`), focused RA-004 criteria selector (`+3`), focused `private_stale_invite_readd` criteria selector (`+7`), ML-019/KE-016 preservation selectors, GM-021 preservation selector, runner scenario discovery, scoped analyzer (`No issues found!`), and iOS 26.2 `private_stale_invite_readd` live proof run `1779185770100` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_invite_readd_RTqRQd`. Broad `groups` remains red at `+223 -4` only on preserved non-RA-004 residuals `BB-007`, `BB-012`, accepted-row `IR-018` fixed-date replay fixture aging past the seven-day retention window, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).

## 0. Row Closure Crosswalk (2026-04-11)

| Row | Closure state | Concrete repo evidence |
|-----|---------------|------------------------|
| `DE-001` | Covered | DE-001 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-001-plan.md`. `send_group_message_use_case.dart` now passes the persisted app timestamp into `callGroupPublish`; `bridge_group_helpers.dart`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/node/pubsub.go` propagate that timestamp into native PubSub payloads while excluding it from arbitrary `extra` metadata. `group_messaging_smoke_test.dart` proves the A/B/C GM-001 sender and receivers persist the same timestamp, group id, message id, sender id, and epoch. `group_multi_party_device_criteria.dart` and `group_multi_party_device_real_harness.dart` add `de001LiveDeliveryProof` requiring group/message/sender/timestamp/epoch matches for Bob and Charlie; `group_multi_party_device_criteria_test.dart` rejects missing proof fields and timestamp mismatch. Evidence passed: focused DE-001 smoke (`+1`), GM-001 criteria selector (`+3`), Go bridge/node timestamp selectors, scoped analyzer (`No issues found!`), iOS binding rebuild, iOS 26.2 `gm001` live proof run `1779131896948` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with message timestamp `2026-05-18T19:22:03.710965Z`. Broad `groups` remains red only on preserved non-DE-001 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-002+, ordering, offline replay, membership mutation, media, notification, or adjacent-row closure is claimed. |
| `DE-002` | Covered | DE-002 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-002-plan.md`. Production code stayed untouched because current main already had the row's bridge cursor retry behavior in `bridge_group_helpers.dart` and `bridge_group_helpers_test.dart`. `group_messaging_smoke_test.dart` now proves Alice's 100 rapid same-sender messages remain in order for Bob, Charlie, and Alice's outgoing rows. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` add the `de002` scenario and ordered-delivery proof, while `group_multi_party_device_criteria_test.dart` accepts valid DE-002 verdicts and rejects missing or out-of-order proof. Evidence passed: focused DE-002 smoke (`+1`), DE-002 criteria selector (`+3`), bridge cursor preservation selector (`+6`), scoped analyzer (`No issues found!`), scoped format/diff checks, and iOS 26.2 `de002` live proof run `1779133511785` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Broad `groups` remains red only on preserved non-DE-002 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-003+, message-id preservation, duplicate replay dedupe, sender self-echo, publish-result semantics, timeout handling, callback routing, native dispatcher panic handling, or adjacent-row closure is claimed. |
| `DE-003` | Covered | DE-003 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-003-plan.md`. Production code stayed untouched because current main already preserved caller-supplied message ids through send, publish, durable replay, live receive dedupe, and failed-message retry paths. `send_group_message_use_case_test.dart` proves an explicit message id is preserved in the publish payload, replay envelope, persisted pending row, and retry payload. `group_resume_recovery_test.dart` proves live delivery, durable replay, duplicate replay dedupe, and failed-message retry keep the explicit id across Alice/Bob/Charlie. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` add the `de003` scenario and `de003MessageIdProof`, while `group_multi_party_device_criteria_test.dart` accepts valid DE-003 verdicts and rejects missing or mismatched proof. Evidence passed: focused DE-003 send selector (`+1`), DE-003 fake-network selector (`+1`), DE-003 criteria selector (`+3`), DE-001/DE-002 preservation selectors, bridge cursor preservation selector (`+6` after serial rerun), scoped analyzer (`No issues found!`), scoped format/diff checks, and iOS 26.2 `de003` live proof run `1779135181457` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with message id `gmp_1779135181457_de003_aliceExplicit_alice`. Broad `groups` remains red only on preserved non-DE-003 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-004+, self-echo, publish-result semantics, timeout handling, callback routing, native dispatcher panic handling, or adjacent-row closure is claimed. |
| `DE-004` | Covered | DE-004 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-004-plan.md`. `drain_group_offline_inbox_use_case.dart` now rehydrates the persisted row in the listener-backed replay branch after `handleReplayEnvelope`, deriving the local delivered receipt for duplicate replay without emitting a second UI row. `drain_group_offline_inbox_use_case_test.dart` proves live plus listener-backed replay keeps one row, preserves first live content/timestamp/sender/key/status, enriches quote/media metadata, commits replay read and local delivered receipts, marks read, and advances the cursor. `group_resume_recovery_test.dart` proves the same live-plus-inbox duplicate path through `FakeGroupPubSubNetwork`. Evidence passed: focused DE-004 direct selector (`+1`), focused DE-004 fake-network selector (`+1`), duplicate/enrichment and unread preservation selectors, scoped analyzer (`No issues found!`), scoped format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-004 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-005+, self-echo, publish-result semantics, callback routing, Go/native, criteria/live-harness, real-device, UI, notification, or adjacent-row closure is claimed. |
| `DE-005` | Covered | DE-005 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-005-plan.md`. `handle_incoming_group_message_use_case.dart` now reconciles sender self-echo duplicate receives against an existing pending/sending outgoing row, promotes the local row to `sent`, clears the wire envelope, preserves local text/timestamp/created-at/retry evidence, and emits `GROUP_HANDLE_INCOMING_MSG_SELF_ECHO_RECONCILED` without creating an incoming duplicate. `handle_incoming_group_message_use_case_test.dart` proves matched self echo reconciliation and mismatched transport identity rejection; `group_message_listener_test.dart` proves the listener emits exactly one reconciled outbound row; `group_resume_recovery_test.dart` proves self echo plus inbox duplicate reconciles the pending row once. Evidence passed: focused DE-005 direct handler bundle (`+2`), focused listener selector (`+1`), focused fake-network resume selector (`+1`), handler/listener/resume/GM-001 preservation selectors, scoped analyzer (`No issues found!`), scoped format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-005 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-006+, publish-result semantics, timeout handling, callback routing, native dispatcher panic handling, Go/native, criteria/live-harness, real-device, UI, notification, or adjacent-row closure is claimed. |
| `DE-006` | Covered | DE-006 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-006-plan.md`. `send_group_message_use_case.dart` now records publish-result fanout evidence that treats `topicPeers` as live fanout only, including expected recipient count, live fanout state, durable inbox state, and `recipientReceiptClaimed: false`. `send_group_message_use_case_test.dart` proves zero, partial, and full live fanout never overclaim delivered/read receipt evidence and that partial fanout plus inbox failure stays retryable. `group_messaging_smoke_test.dart` proves full live fanout remains sender-visible `sent`, not delivered; `group_resume_recovery_test.dart` proves partial live fanout does not claim offline-recipient receipt before durable inbox replay. Evidence passed: focused DE-006 send selectors (`+2`), focused resume selector (`+1`), focused smoke selector (`+1`), WU-3 preservation (`+29`), Section 11 resume preservation (`+2`), GE-010/GE-011 smoke preservation (`+2`), GO-002 retry preservation (`+1`), scoped analyzer (`No issues found!`), scoped format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-006 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-007+, timeout handling, receipt protocol generation, callback routing, native dispatcher panic handling, Go/native, criteria/live-harness, real-device, UI, notification, or adjacent-row closure is claimed. |
| `DE-007` | Covered | DE-007 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-007-plan.md`. Current main production behavior already stores durable replay for zero-peer active recipients, so production code stayed untouched. `send_group_message_use_case_test.dart` proves zero live topic peers return `successNoPeers`, persist sender status `sent`, store encrypted durable replay for Bob and Charlie, clear retry/wire payloads, and record no recipient receipt claim. `group_resume_recovery_test.dart` proves active Bob and Charlie receive Alice's zero-peer message exactly once through durable replay. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` add the `de007` scenario and `de007ZeroPeerProof`, while `group_multi_party_device_criteria_test.dart` accepts valid DE-007 verdicts and rejects missing or mismatched proof. Evidence passed: focused DE-007 send selector (`+1`), focused DE-007 fake-network selector (`+1`), focused DE-007 criteria selector (`+3`), DE-006/GP-005/GP-007/GO-001/GO-002 send preservation (`+6`), GO-002 retry preservation (`+1`), Section 11 resume preservation (`+4`), DE-006/GE-010/GE-011 smoke preservation (`+3`), adjacent criteria preservation (`+20`), scoped analyzer (`No issues found!`), scoped format/diff checks, and iOS 26.2 `de007` live proof run `1779140605428` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_de007_9O8Ctq`, message id `gmp_1779140605428_de007_aliceZeroPeer_alice`, and verdict `de007 verdicts valid for alice, bob, charlie`. Broad `groups` remains red only on preserved non-DE-007 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-008+, timeout handling, callback routing, native dispatcher panic handling, receipt protocol generation, UI, notification, media, or adjacent-row closure is claimed. |
| `DE-008` | Covered | DE-008 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-008-plan.md`. Production code stayed untouched because current main already routes `BRIDGE_TIMEOUT` plus durable inbox custody to visible `sent` success and timeout without custody to failed-message retry ownership. `send_group_message_use_case_test.dart` row-names and strengthens the durable-timeout selector and adds `DE-008 publish timeout without durable inbox custody leaves one visible failed retryable row`, proving one visible outgoing failed row, retained `wireEnvelope`/`inboxRetryPayload`, failed-message retry ownership, and exclusion from inbox-store retry ownership. `retry_failed_group_messages_use_case_test.dart` adds `DE-008 retry of timeout-owned failed row reuses message id and clears invisible failed state`, proving retry sends the same `messageId`, leaves one saved `sent` row, clears retry state, and removes failed-row ownership. `group_resume_recovery_test.dart` adds a test-local publish-timeout bridge knob and `DE-008 publish timeout no custody retries over fake network and recipient sees one row`, proving host fake-network recovery with the same id and no duplicate sender/recipient row. Evidence passed: focused DE-008 send selector bundle (`+2`), focused retry selector (`+1`), focused fake-network selector (`+1`), send preservation (`+9`), retry preservation (`+3`), GO-002 inbox-store retry preservation (`+1`), resume preservation (`+6`), scoped analyzer (`No issues found!`), scoped format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-008 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-009+, callback routing, native dispatcher panic handling, receipt protocol generation, criteria/live-harness, real-device, UI, notification, media, or adjacent-row closure is claimed. |
| `DE-009` | Covered | DE-009 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-009-plan.md`. Production code stayed untouched because current main already preserves `onGroupMessageReceived` across `GoBridgeClient.reinitialize()` and routes `group_message:received` to that callback. `go_bridge_client_test.dart` adds a test-local EventChannel listen/cancel mock and `DE-009 group message callback survives reinitialize and receives event once`, proving a pre-existing group callback survives `initialize()` then `reinitialize()` and receives exactly one subsequent group message payload. Evidence passed: focused DE-009 selector (`+1`), full bridge-client owner suite (`+78`), scoped analyzer (`No issues found!`), scoped format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-009 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-010+, dispatcher panic handling, dispatcher pressure/overflow recovery, receipt protocol generation, group listener/app-level delivery, fake-network, Go/native, relay, criteria/live-harness, real-device, UI, notification, media, or adjacent-row closure is claimed. |
| `DE-010` | Covered | DE-010 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-010-plan.md`. Production `go-mknoon/node/event_dispatcher.go` stayed untouched because current main already recovers and logs callback panics in `EventDispatcher.deliver`. `go-mknoon/node/node_test.go` adds `TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure`, forcing the first `group_message:received` callback invocation to panic, then proving the next two group events dispatch in FIFO order with message ids `de010-after-1` and `de010-after-2`, no dropped/coalesced events, queue depth `0`, and recovered panic log evidence containing the event name and panic reason. Evidence passed: focused DE-010 selector (`ok github.com/mknoon/go-mknoon/node 0.471s`), adjacent dispatcher selector (`ok github.com/mknoon/go-mknoon/node 1.581s`), gofmt, scoped diff check, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-010 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-011 pressure, DE-012 overflow replay, Dart EventChannel recovery, Flutter listener/UI, fake-network, relay, simulator/device, receipt protocol, notification, media, or adjacent-row closure is claimed. |
| `DE-011` | Covered | DE-011 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-011-plan.md`. Production `go-mknoon/node/event_dispatcher.go` stayed untouched because current main already preserves message-bearing events in the FIFO dispatcher queue, records below-capacity pressure diagnostics, and drops only at capacity. `go-mknoon/node/node_test.go` adds `TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure`, configuring queue capacity 6, gating the first callback, emitting five `group_message:received` events interleaved with coalescible status events, and proving every message id/sequence arrives exactly once in FIFO order while `group:dispatcher_pressure` reports `near_overflow`, `lastEvent == group_message:received`, `queueDepth < maxQueueSize`, and no overflow/dropped residue. Evidence passed: focused DE-011 selector (`ok github.com/mknoon/go-mknoon/node 0.623s`), adjacent dispatcher selector (`ok github.com/mknoon/go-mknoon/node 1.598s`), full Go node package (`ok github.com/mknoon/go-mknoon/node 381.407s`), gofmt, scoped diff check, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-DE-011 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-012 overflow replay recovery, DE-013 schema validation, DE-019 EventChannel recovery, DE-020 starvation, Flutter listener/UI, fake-network, relay, simulator/device, receipt protocol, notification, media, or adjacent-row closure is claimed. |
| `DE-012` | Covered | DE-012 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-012-plan.md`. `group_message_listener.dart` now consumes `group:dispatcher_overflow` diagnostics for `lastEvent == group_message:received`, coalesces concurrent replay requests, and emits requested/coalesced/ignored/unavailable/done/error flow evidence. `main.dart` wires runtime overflow recovery to `drainGroupOfflineInbox` with the live listener replay handler, media/reaction repos, pending key repair repo, history gap repair repo, and self peer id. `group_test_user.dart` exposes test harness diagnostic/recovery wiring. `node_test.go` adds `TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery`; `group_message_listener_test.dart` adds the row-owned coalescing proof; `group_resume_recovery_test.dart` adds the fake-network inbox replay proof. Evidence passed: focused DE-012 Go selector bundle (`ok github.com/mknoon/go-mknoon/node 0.857s`), focused listener selector (`+1`), focused fake-network selector (`+1`), affected bridge diagnostic preservation selector (`+1`), scoped analyzer (`No issues found!`), gofmt, Dart format, and scoped diff check. Broad `groups` remains red only on preserved non-DE-012 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. No DE-013 schema validation, DE-014 decryption repair, DE-015 payload parse recovery, DE-019 EventChannel recovery, DE-020 starvation, simulator/device, 3-party E2E, UI, notification, media, or adjacent-row closure is claimed. |
| `DE-013` | Covered | DE-013 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-013-plan.md`. `group_message_listener.dart` now validates incoming group message event maps before typed extraction/persistence, requiring non-empty `groupId`/`senderId`, non-negative `keyEpoch` for non-system user messages, typed optional wire fields, and valid media list/map entries while preserving signed system replay payloads that omit legacy `keyEpoch`. Rejected events emit `GROUP_MESSAGE_LISTENER_SCHEMA_REJECTED` with safe reason metadata and create no persisted row or stream emission. `group_message_listener_test.dart` adds `DE-013 malformed group message schema rejects before persistence and valid later event persists`; `group_resume_recovery_test.dart` adds `DE-013 malformed pubsub message is rejected and later valid delivery persists`. Evidence passed: focused listener selector (`+1`), focused fake-network selector (`+1`), GM-032 dissolved replay preservation (`+1`), GM-007/KE-018 history-window preservation (`+1`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. Broad `groups` remains red at `+204 -3` only on preserved non-DE-013 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No DE-014 decryption recovery, DE-015 payload parse failure, DE-016 validation diagnostics, EventChannel recovery, dispatcher starvation, simulator/device, 3-party E2E, UI, notification, media, relay, or adjacent-row closure is claimed. |
| `DE-014` | Covered | DE-014 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-014-plan.md`. Production decryption-repair behavior stayed untouched because current main already has live decryption-failure pending-key placeholders, durable replay pending-key repair, and key-arrival retry behavior. `group_test_user.dart` now exposes row-owned pending-key repair repository injection for fake-network tests. `group_message_listener_test.dart` adds `DE-014 decryption failure queues repair placeholder and later valid event still persists`, proving a live `group:decryption_failed` diagnostic creates one safe placeholder and repair request, redacts secret error text from flow evidence, and allows later valid live delivery. `group_resume_recovery_test.dart` adds a local pending-key repair repository helper and `DE-014 decrypt failure repairs from durable replay and preserves later fake-network delivery`, proving live placeholder creation, durable replay placeholder supersession, offline repair request, key-arrival retry, final delivered row, and later fake-network delivery. Evidence passed: focused listener selector (`+1`), focused fake-network selector (`+1`), GO-004 preservation (`+1`), GEK002 durable repair preservation (`+1`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. Broad `groups` remains red at `+205 -3` only on preserved non-DE-014 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No DE-015 payload parse failure, DE-016 validation diagnostics, DE-017 membership/content ordering, EventChannel recovery, dispatcher starvation, simulator/device, 3-party E2E, UI, notification, media, relay, or adjacent-row closure is claimed. |
| `DE-015` | Covered | DE-015 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-015-plan.md`. Production app/native behavior stayed untouched. The source native Go DE-015 selector was not duplicated because current main already has equivalent or stronger native continuity coverage in `TestGP023ReceivePathContinuesAfterMalformedPayload`, which proves malformed payload parse diagnostics, no malformed receive/plaintext side effect, and later valid `group_message:received` delivery. `go_bridge_client_test.dart` renames/extends the existing payload-parse diagnostic selector to `DE-015 payload parse diagnostic does not poison later group message callback`, proving the diagnostic reaches `groupDiagnosticEventStream` without invoking the message callback and a later valid group message callback fires exactly once. `fake_group_pubsub_network.dart` adds minimal diagnostic stream registration plus `emitPayloadParseFailureDiagnostic`; `group_resume_recovery_test.dart` adds `DE-015 payload parse diagnostic does not poison later fake-network delivery`, proving the fake-network diagnostic creates no visible row and later valid delivery persists exactly once. Evidence passed: focused bridge selector (`+1`), focused fake-network selector (`+1`), GP-023 native continuity selector (`ok github.com/mknoon/go-mknoon/node 2.128s`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. Broad `groups` remains red at `+206 -3` only on preserved non-DE-015 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No DE-016 validation diagnostics, DE-017 membership/content ordering, EventChannel recovery, dispatcher starvation, simulator/device, 3-party E2E, UI, notification, media, relay, or adjacent-row closure is claimed. |
| `DE-016` | Covered | DE-016 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-016-plan.md`. Production app/native behavior stayed untouched. The source native Go DE-016 selector was not duplicated because current main already has equivalent or stronger validation-rejection safety coverage through GA-002 non-member rejection, GA-026 all-reason privacy-safe diagnostics, and GO-005 validation diagnostic rate-limit proof. `go_bridge_client_test.dart` renames/extends the existing validation-rejection diagnostic selector to `DE-016 validation reject diagnostic reaches safe logs without group message callback`, proving the diagnostic reaches `groupDiagnosticEventStream`, invokes no group-message callback, omits raw ids, and emits safe `GROUP_VALIDATION_REJECTED` flow evidence. `fake_group_pubsub_network.dart` adds minimal `emitValidationRejectedDiagnostic`; `group_resume_recovery_test.dart` adds `DE-016 validation reject diagnostic stays safe and later fake-network delivery persists`, proving the fake-network diagnostic creates no visible row and later valid delivery persists exactly once. Evidence passed: focused bridge selector (`+1`), focused fake-network selector (`+1`), native validation-rejection preservation bundle (`ok github.com/mknoon/go-mknoon/node 8.221s`), GO-003 bridge preservation (`+1`), DE-015 fake-network preservation (`+1`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. Broad `groups` remains red at `+207 -3` only on preserved non-DE-016 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No DE-017 membership/content ordering, EventChannel recovery, dispatcher starvation, simulator/device, 3-party E2E, UI, notification, media, relay, or adjacent-row closure is claimed. |
| `DE-017` | Covered | DE-017 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-017-plan.md`. `GroupMember` config JSON now preserves `joinedAt`; `GroupMessageListener` buffers live membership-dependent content until the matching add-membership watermark, flushes only content inside the sender's joined interval, repairs post-removal content, and leaves replay handling unbuffered to preserve offline replay contracts. The source global handler before-joined guard was not imported because it conflicts with existing offline replay preservation; the DE-017 rule is enforced in the listener flush path. `group_member_test.dart` adds the joined-interval config round trip; `group_message_listener_test.dart` adds pre-add buffering and post-removal repair selectors; `group_resume_recovery_test.dart` adds the fake-network convergence selector; `group_multi_party_device_criteria_test.dart` adds three DE-017 criteria selectors; the `de017` runner/live-harness scenario was imported. Evidence passed: focused model selector (`+1`), listener DE-017 selector (`+2`), fake-network DE-017 selector (`+1`), criteria DE-017 selector (`+3`), GM-014/ML-009/KE-012/DE-014 listener preservation (`+4`), GM-014 key-update preservation (`+1`), GM-014/GM-034/GM-035/ML-009/KE-012 membership preservation (`+5`), GE-004/GE-008/GE-009 smoke preservation (`+3`), adjacent criteria preservation (`+28`), scoped analyzer (`No issues found!`), Dart format, scoped diff check, and iOS 26.2 `de017` live proof run `1779152294735` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with verdict `de017 proof passed: de017 verdicts valid for alice, bob, charlie`. Broad `groups` remains red at `+208 -3` only on preserved non-DE-017 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`); affected drain preservation still has existing offline replay residuals `GM-033` and `GEK003` while `GM-014` and `GEK002` pass. No DE-018 unknown-event recovery, EventChannel recovery, dispatcher starvation, UI, notification, media, relay, or adjacent-row closure is claimed. |
| `DE-018` | Covered | DE-018 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-018-plan.md`. Production bridge behavior stayed untouched because current main already logs/ignores unknown push events and routes known group message/reaction events. `go_bridge_client_test.dart` adds `DE-018 unknown group event is ignored without blocking known callbacks`, proving an unknown future `group:future_protocol_probe` logs as an unknown push event, invokes no known group callbacks, and does not block later `group_message:received` and `group_reaction:received` callbacks from firing exactly once with the expected payloads. Evidence passed: focused DE-018 selector (`+1`), adjacent bridge preservation selectors `DE-009|DE-015|DE-016|GO-003|GO-004|GO-008` (`+8`), full bridge owner suite (`+79`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. No broad named gate or iOS 26.2 live proof was required because DE-018 is host bridge-router proof; source `3-Party E2E` is `N/A`. No DE-019 EventChannel recovery, DE-020 dispatcher starvation, UI, notification, relay, simulator/device, or adjacent-row closure is claimed. |
| `DE-019` | Covered | DE-019 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-019-plan.md`. `go_bridge_client.dart` now routes EventChannel `onError` and `onDone` through a guarded recovery handler, emits safe error/done and recovery-requested/success/failure flow evidence, marks `_initialized=false` while unhealthy, logs push diagnostics, and asynchronously reinitializes/resubscribes while preserving callbacks; intentional `reinitialize()`/`dispose()` cancellation is suppressed from recursive recovery. `go_bridge_client_test.dart` adds `DE-019 EventChannel error emits diagnostics, recovers, and preserves group callback` and `DE-019 EventChannel done emits diagnostics, recovers, and preserves group callback`, proving second EventChannel listens, callback survival, sanitized diagnostics, and post-recovery `group_message:received` delivery. Evidence passed: focused DE-019 selector (`+2`), adjacent bridge preservation selectors `DE-009|DE-015|DE-016|DE-018|GO-003|GO-004|GO-008|OB-007` (`+9`; no OB-007 selector exists yet in current main), full bridge owner suite (`+81`), scoped analyzer (`No issues found!`), Dart format, and scoped diff check. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+208 -3` only on preserved non-DE-019 residuals `BB-007`, `BB-012`, and `GM-029`; no iOS 26.2 live proof was required because source `3-Party E2E` is `N/A`. No DE-020 dispatcher starvation, OB-007 lifecycle health proof, ST-011 rapid reinitialize stress, UI, notification, relay, simulator/device, or adjacent-row closure is claimed. |
| `DE-020` | Covered | DE-020 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-DE-020-plan.md`. Production behavior stayed untouched because current main already has the dispatcher, bridge routing, and fake-network delivery behavior required by the row; only missing row-owned proofs were imported. `go-mknoon/node/node_test.go` adds `TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage`, proving a 10,000-character `group_message:received` followed by a normal group message drains FIFO with delivered `2`, coalesced `0`, dropped `0`, and queue depth `0`. `go_bridge_client_test.dart` adds `DE-020 large group payload does not starve later group callback`, proving max-length and normal follow-up group events both reach the group callback once and in order. `group_resume_recovery_test.dart` adds `DE-020 large payload does not starve later fake-network delivery`, proving max-length and normal fake-network sends persist exactly once, in order, with two publishes and two live deliveries using current main's existing fake-network counters instead of importing unrelated source `deliveryRecords` fixture work. Evidence passed: focused native DE-020 selector (`ok github.com/mknoon/go-mknoon/node 0.543s`), focused bridge selector (`+1`), focused fake-network selector (`+1`), native DE-011/DE-012/dispatcher preservation (`ok github.com/mknoon/go-mknoon/node 0.782s`), DE-019/overflow bridge preservation (`+3`), DE-012 listener and fake-network preservation (`+1` each), scoped analyzer (`No issues found!`), gofmt, Dart format, and scoped diff check. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+209 -3` only on preserved non-DE-020 residuals `BB-007`, `BB-012`, and `GM-029`; no iOS 26.2 live proof was required because source `3-Party E2E` is recommended only and no current DE-020 live scenario exists. No ST-005 queue storm, DE-012 overflow replay changes, EventChannel recovery, fake-network route-mode/delivery-record fixture import, UI, notification, relay, simulator/device, or adjacent-row closure is claimed. |
| `IR-001` | Covered | IR-001 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-001-plan.md`. Production code stayed untouched. The source host fake-network selector was skipped as already present because current main's `temporary partition replays missed backlog in cursor order and resumes live delivery after heal` proves active-member missed backlog replay, exactly-once receipt, cursor order, and post-heal live delivery. Missing row-owned device artifacts were imported: `group_multi_party_device_criteria.dart` validates `ir001OfflineReconnectProof`; `group_multi_party_device_criteria_test.dart` adds valid/missing/count-mismatch/live-proof rejection coverage; `run_group_multi_party_device_real.dart` lists and runs `ir001`; and `group_multi_party_device_real_harness.dart` drives Alice/Charlie online, Bob offline seed/relaunch, Bob's offline drain, and the post-drain live message. Evidence passed: focused IR-001 criteria selector (`+4`), runner discovery for `ir001`, already-present fake-network preservation selector (`+1`), adjacent criteria preservation (`+2`), scoped analyzer (`No issues found!`), Dart format, iOS 26.2 `ir001` live proof run `1779156694294` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir001_kXLN8r` and verdict `ir001 proof passed: ir001 verdicts valid for alice, bob, charlie`. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+209 -3` only on preserved non-IR-001 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-002+, cursor pagination, retention cutoff, history repair, media replay breadth, production bridge/native changes, UI, notification, relay, or adjacent-row closure is claimed. |
| `IR-002` | Covered | IR-002 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-002-plan.md`. Production code stayed untouched. `bridge_group_helpers_test.dart` proves `GroupInboxPage` message list, next cursor, request limit, and history-gap metadata parsing for cursor replay pages. `drain_group_offline_inbox_use_case_test.dart` proves a first-page-only drain persists the next cursor, a restart/fresh bridge resumes at that cursor, remaining pages drain exactly once, the completed drain advances to a synthetic since cursor, and post-complete redrain creates no duplicates. Evidence passed: focused IR-002 bridge selector (`+1`), focused IR-002 drain selector (`+1`), bridge history-gap preservation (`+1`), GI-026 app history-gap preservation (`+1`), fake-network partition-heal preservation (`+1`), GR-015/GR-016 resume preservation (`+2`), scoped analyzer (`No issues found!`), Dart format, and `git diff --check`. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+209 -3` only on preserved non-IR-002 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). The sampled COMPLETE_1 GI-017 selector still fails in current main with `Expected: <120> / Actual: <0>` at `drain_group_offline_inbox_use_case_test.dart:9694` and was not rewritten because it is not an IR-002 source-row import. No IR-003+, timestamp retrieval, retention cutoff, removed/re-added replay eligibility, inbox recipient targeting, production bridge/native changes, UI, notification, relay, live harness, or iOS 26.2 proof is claimed. |
| `IR-003` | Covered | IR-003 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-003-plan.md`. `go-mknoon/node/group_inbox.go` now applies the existing inclusive boundary helper to direct legacy `GroupInboxRetrieve`, while the already-present synthetic-cursor fallback and Dart high-water cursor behavior were left unchanged. `go-mknoon/node/group_inbox_test.go` adds `TestIR003GroupInboxRetrieveUsesInclusiveSinceBoundary` and reconciles GI-009 request-shape expectations to the inclusive lower bound. `drain_group_offline_inbox_use_case_test.dart` proves timestamp high-water replay includes same-boundary messages and dedupes repeated ids, and `group_resume_recovery_test.dart` proves the same boundary behavior through fake-network replay. Evidence passed: focused native IR-003/GI-009/synthetic selector bundle, focused app IR-003 selector, focused fake-network IR-003 selector, native ST-004 preservation, relay strict lower-bound preservation, IR-002/cursor/tampered replay/partition-heal preservation, scoped analyzer (`No issues found!`), baseline gate, `git diff --check`, and no-live-proof classification. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-003 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). The sampled ML-008 preservation selector still fails in current main with `Expected: not null / Actual: <null>` at `drain_group_offline_inbox_use_case_test.dart:1413` and was not rewritten because it is outside IR-003 source-row import. No IR-004+, retention cutoff, removed/re-added replay eligibility, inbox recipient targeting, history repair, cursor pagination expansion, relay ACL, UI, notification, live harness, or iOS 26.2 proof is claimed. |
| `IR-004` | Covered | IR-004 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-004-plan.md`. Production code stayed untouched because current main already has replay recipient entitlement skipping and existing removal-cutoff coverage. `drain_group_offline_inbox_use_case_test.dart` adds `IR-004 removed offline member rejects post-removal replay before decrypt`, proving stale removed Charlie skips A/B post-removal replay envelopes whose `recipientPeerIds` exclude Charlie before payload verification/decrypt, persists no protected plaintext or visible placeholders, creates no repair exposure, and emits recipient-skip flow evidence. `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, and `group_multi_party_device_real_harness.dart` add `ir004PostRemovalReplayProof` validation and live proof fields to the existing `private_offline_remove` scenario. Evidence passed: focused IR-004 app selector (`+1`), focused IR-004 criteria selector (`+3`), ML-006 preservation (`+1`), `private_offline_remove` criteria preservation (`+8`), GK-022 preservation (`+1`), scoped analyzer (`No issues found!`), scenario discovery, iOS 26.2 `private_offline_remove` proof run `1779160203612` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_remove_S9tfia` and verdict `private_offline_remove proof passed: private_offline_remove verdicts valid for alice, bob, charlie`. The sampled GK-023 selector still fails in current main with `Expected: null / Actual: GroupModel:<GroupModel(id: group-1, name: GK-023 Group, type: chat)>` at `drain_group_offline_inbox_use_case_test.dart:4665` and was not rewritten because it is a separate replay-window residual. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-004 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-005+, re-add replay boundaries, relay ACL internals, media privacy, UI, notification, Android, physical iOS, macOS app-peer roles, or adjacent-row closure is claimed. |
| `IR-005` | Covered | IR-005 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-005-plan.md`. Production code stayed untouched because current main already has the row's re-added member replay-window behavior through recipient-aware replay envelopes, exact key-generation lookup, and existing GM-007/KE-018 coverage. `drain_group_offline_inbox_use_case_test.dart` extends the existing KE-018 direct proof as `IR-005 KE-018 drains only replay windows addressed to re-added member`, proving Charlie keeps pre-removal replay, skips removed-window replay, keeps post-readd replay, and issues only two distinct decrypt requests for the two entitled envelopes. `group_membership_smoke_test.dart` extends the existing GM-007/KE-018 fake-network selector with the IR-005 row identity. `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` add `ir005ReaddReplayProof` validation, criteria tests, stale installed app guard, and live proof fields to the existing `gm007` scenario. Evidence passed: focused IR-005 app selector (`+1`), focused IR-005 fake-network selector (`+1`), focused IR-005 criteria selector (`+3`), KE-018 preservation (`+1`), GM-007 preservation (`+9`), GM-019 preservation (`+8`), scoped analyzer (`No issues found!`), and iOS 26.2 `gm007` proof run `1779161721700` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_zTSoIb` and verdict `gm007 proof passed: gm007 verdicts valid for alice, bob, charlie`. Existing replay-window residual selectors still fail in current main and were not rewritten because they are separate residuals: `GM-033` at `drain_group_offline_inbox_use_case_test.dart:4347`, `GK-023` at `:4665`, and `GI-019` at `:4960`. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-005 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-006+, active-recipient closure, relay ACL internals, media replay breadth, UI, notification, Android, physical iOS, or adjacent-row closure is claimed. |
| `IR-006` | Covered | IR-006 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-006-plan.md`. Production code stayed untouched because current main already computes send-time `recipientPeerIds` from the active membership snapshot using membership cutoff, deliverable identity filtering, sender exclusion, and recipient dedupe. `send_group_message_use_case_test.dart` adds `IR-006 group inbox store targets exact active recipients at send time`, proving a send after Charlie has been removed produces `group:inboxStore.recipientPeerIds == [Bob]` and excludes Alice, removed Charlie, declined, expired, and never-joined peer ids. `group_messaging_smoke_test.dart` extends the existing KE-021 fake-network proof as `IR-006 KE-021 removed member is not targeted by future fake-network key or inbox payloads`, proving remove-then-send ordering targets only remaining active Bob, excludes Alice/removed Charlie/declined/expired/never-joined ids, and Charlie receives no post-removal message. Evidence passed: focused IR-006 direct selector (`+1`), focused IR-006 fake-network selector (`+1`), scoped analyzer (`No issues found!`), GI-004 preservation (`+1`), GM-019 app preservation (`+1`), DE-007 preservation (`+1`), KE-021 drain and rotation preservation (`+2`), and GM-019 member-removal preservation (`+1`). `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-006 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-007 retry ownership, relay-side ACLs, media `allowedPeers`, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-007` | Covered | IR-007 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-007-plan.md`. Production code stayed untouched because current main already owns publish-success/inbox-failure rows through visible `pending` inbox-store retry and publish-failure/inbox-failure rows through failed-message retry. `send_group_message_use_case_test.dart` adds `IR-007 publish success plus inbox failure is pending and inbox retry closes same id` and `IR-007 publish failure plus inbox failure is failed and owned by message retry`, proving the pending branch clears `wireEnvelope`, keeps `inboxRetryPayload`, is selected by inbox-only retry, and stores the same message id once, while the failed branch retains publish retry data, is excluded from inbox-only retry, and stays visible as one failed row. `retry_failed_group_inbox_stores_use_case_test.dart` adds `IR-007 inbox retry sends same pending message id once without duplicate rows`, proving retry sends the persisted message id, clears retry state, and a second pass does not duplicate or resend. `group_resume_recovery_test.dart` extends the existing fake-network retry-owner proofs as `IR-007 rapid pause/resume closes pending live-peer send via inbox retry exactly once` and `IR-007 DE-008 publish failure branch retries over fake network with same id and one row`. Evidence passed: focused IR-007 send selectors (`+2`), focused IR-007 inbox retry selector (`+1`), focused IR-007 fake-network selectors (`+2`), scoped analyzer (`No issues found!`), send preservation (`+8`), GO-002 retry preservation (`+1`), DE-008 failed-message preservation (`+1`), resume preservation (`+5`), and DE-006 smoke preservation (`+1`). `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+210 -3` only on preserved non-IR-007 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-008 cursor/ack rollback, IR-009 persistence-before-ack, relay-side ACLs, media, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-008` | Covered | IR-008 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-008-plan.md`. Production code stayed untouched because current main already retrieves before page writes and commits cursor/receipts only inside `runInboxPageTransaction` after successful page processing. `drain_group_offline_inbox_use_case_test.dart` adds `IR-008 retrieve failure leaves cursor and ack state unchanged until retry`, proving a failed `group:inboxRetrieveCursor` leaves the durable cursor unchanged, persists no message row, writes no delivered/read receipt state, retries the same cursor, then persists the page exactly once and advances the cursor only after success. The imported fixture seeds current main's local membership precondition inside the row-owned test. `group_resume_recovery_test.dart` adds `_FailFirstCursorInboxBridge` and `IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once`, proving the first fake-network replay retrieve fails with no message, cursor, or receipt side effect, then retries the same cursor and drains the missed message once with the original id/text/sender. Evidence passed: focused IR-008 direct selector (`+1`), focused IR-008 fake-network selector (`+1`), scoped analyzer (`No issues found!`), fake-network preservation (`+4`), bridge-helper preservation (`+10`), and diff hygiene. The drain preservation bundle returned `+9 -1` only on the unrelated non-IR-008 `GE-018` local-membership fixture residual. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+211 -3` only on preserved non-IR-008 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-009 persistence-before-ack, history repair, relay-side ACLs, media, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-009` | Covered | IR-009 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-009-plan.md`. Production code stayed untouched because current main already processes replay messages before the Phase 2 cursor/receipt transaction and propagates local save failures before cursor/ack commit. `drain_group_offline_inbox_use_case_test.dart` adds `IR-009 persistence failure retries same page before cursor or ack commit`, proving local save failure leaves no message row, durable cursor, delivered/read receipt, or read-state ack; the retry requests the same cursor, persists the same message exactly once, commits delivered/read ack state only after success, and advances the cursor only after the successful page. The imported fixture seeds current main's local membership precondition inside the row-owned test. `group_resume_recovery_test.dart` adds `IR-009 failed replay persistence retries same cursor and stores missed fake-network message once`, proving a fake-network offline recipient's first local persistence attempt fails with no message, cursor, or receipt side effect, then retries the same cursor and stores the missed message once with the original id/text/sender. Evidence passed: focused IR-009 direct selector (`+1`), focused IR-009 fake-network selector (`+1`), scoped analyzer (`No issues found!`), drain preservation bundle (`+8`), fake-network preservation bundle (`+5`), and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+212 -3` only on preserved non-IR-009 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-010/IR-011 history-gap parsing or repair request validation, IR-012 hash/head repair verification, relay-side ACLs, media, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-010` | Covered | IR-010 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-010-plan.md`. Production code stayed untouched because current main already parses cursor `historyGaps`, surfaces `historyGapCount`, and persists valid cursor gaps into the drain-side repair lifecycle. `bridge_group_helpers_test.dart` adds `IR-010 parses and surfaces valid cursor historyGaps while filtering invalid entries`, proving valid gap entries are parsed while invalid entries are ignored and the count reflects accepted gaps. `drain_group_offline_inbox_use_case_test.dart` adds `IR-010 drains valid cursor historyGaps into repair lifecycle and ignores invalid gaps`, proving only valid gap identity/source/cursor data creates a persisted repair lifecycle row and invalid entries create no repairs or messages. Evidence passed: focused IR-010 parser selector (`+1`), focused IR-010 drain selector (`+1`), scoped analyzer (`No issues found!`), bridge parser preservation (`+3`), drain/history repair preservation (`+5`), drain follow-up invariant selector (`+1`), native GI-011 cursor history-gap preservation (`ok github.com/mknoon/go-mknoon/node 0.606s`), Dart format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+212 -3` only on preserved non-IR-010 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-011 repair request validation, IR-012 hash/head repair verification, relay-side ACLs, media, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-011` | Covered | IR-011 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-011-plan.md`. Production code stayed untouched because current main already normalizes native repair requests, surfaces bridge invalid input, and validates wrong group/gap/source responses before applying repaired history. `go-mknoon/node/group_inbox_test.go` adds `TestIR011GroupHistoryRepairRange_NormalizesAndRejectsIdentity`, proving identity/source normalization, default limit, and invalid group/gap/source rejection before node or relay use. `go_bridge_client_test.dart` adds `IR-011 history repair helper normalizes request identity and surfaces invalid input`, proving typed payload routing and `INVALID_INPUT` surfacing. `drain_group_offline_inbox_use_case_test.dart` adds `IR-011 history repair request validates gap identity and source peer before mutation`, proving wrong-group gaps are skipped, unauthorized/self sources are not requested, wrong group/gap/source responses insert no messages, and only the valid fallback repairs the gap. `group_resume_recovery_test.dart` adds the fake-network version with `ir011-fake-valid-fallback`. Evidence passed: focused native IR011 selector (`ok github.com/mknoon/go-mknoon/node 0.546s`), focused bridge/drain/fake-network selectors (`+1` each), scoped analyzer (`No issues found!`), Dart format/gofmt, Go node/bridge repair preservation (`ok node 0.736s`, `ok bridge 1.121s`), drain/history preservation (`+6`), fake-network history preservation (`+1`), and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+213 -3` only on preserved non-IR-011 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-010 parsing, IR-012 hash/head validation, IR-013 unauthorized source injection, retention cutoff, relay privacy, media, UI, notification, criteria/live harness, iOS/live proof, or adjacent replay-row closure is claimed. |
| `IR-012` | Covered | IR-012 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-012-plan.md`. Production code stayed untouched because current main already validates repair `headMessageId`, response `rangeHash`, and computed range hash before applying repaired history, records rejection diagnostics, and continues to later candidate sources. `drain_group_offline_inbox_use_case_test.dart` adds `IR-012 history repair rejects wrong hash and head before fallback insert`, proving a bad-hash source inserts none of its supplied messages, a wrong-head source does not complete repair or stop fallback, and the later valid source inserts only the valid repaired range. `group_resume_recovery_test.dart` adds `IR-012 fake-network repair rejects wrong hash and head then restores range before live delivery`, proving the same rejection/fallback behavior through fake-network resume recovery and later live delivery. Evidence passed: focused IR-012 direct selector (`+1`), focused IR-012 fake-network selector (`+1`), scoped analyzer (`No issues found!`), Dart format, affected GI-026/GI-031/GI-032/GI-033/PREREQ preservation (`+7`), fake-network history preservation (`+1`), and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+214 -3` only on preserved non-IR-012 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-010 parsing, IR-011 repair request validation, IR-013 unauthorized source injection, retention cutoff, relay privacy, media, UI, notification, criteria/live harness, iOS/live proof, or adjacent replay-row closure is claimed. |
| `IR-013` | Covered | IR-013 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-013-plan.md`. Production code stayed untouched because current main already records unauthorized repair candidates as `unauthorized_source`, requests repair only from current authorized member sources, validates returned `sourcePeerId` against the requested source before applying repaired history, and continues to later candidate sources. `drain_group_offline_inbox_use_case_test.dart` adds `IR-013 unauthorized repair source cannot inject before fallback`, proving unauthorized `peer-rogue` is recorded but receives no `group:historyRepairRange` request, a forged response claiming `peer-rogue` is rejected on an authorized source request, and the authorized fallback inserts only `ir013-valid-fallback`. `group_resume_recovery_test.dart` adds `IR-013 fake-network unauthorized repair source cannot inject before fallback`, proving the same unauthorized-source rejection and fallback behavior through fake-network resume recovery. Evidence passed: focused IR-013 direct selector (`+1`), focused IR-013 fake-network selector (`+1`), scoped analyzer (`No issues found!`), Dart format, affected IR-011/IR-012/GI-031/GI-032/GI-033/PREREQ preservation (`+8`), fake-network history preservation (`+3`), and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+215 -3` only on preserved non-IR-013 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-010 parsing, IR-011 request identity/source validation, IR-012 hash/head validation, relay-side ACLs, media, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-014` | Covered | IR-014 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-014-plan.md`. Production code stayed untouched because current main already builds group offline replay with `group.encrypt`, sends only the opaque replay envelope through `group:inboxStore`, and omits retired native push preview fields. `send_group_message_use_case_test.dart` adds `IR-014 group inbox store relay payload omits plaintext and secrets`, proving relay-visible payload keys are limited to `groupId`, `message`, and `recipientPeerIds`, with no plaintext, sender display name, group key, invite/member secrets, `pushTitle`, or `pushBody`. `group_resume_recovery_test.dart` adds `IR-014 fake-network inbox store relay payload is opaque while delivery succeeds`, proving the same opacity while Bob still receives the message through fake-network delivery. Native Go opacity was skipped as already present because `group_inbox_test.go` already has `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope`, and the equivalent proof passed with GI-035 preservation. Evidence passed: focused IR-014 direct selector (`+1`), focused IR-014 fake-network selector (`+1`), scoped analyzer (`No issues found!`), native equivalent opacity selector, direct privacy/recipient/retry preservation selectors (`+6`), inbox retry preservation (`+1`), fake-network IR-007 preservation (`+2`), fake-network IR-006 preservation (`+1`), broader Go inbox payload-shape preservation, format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+216 -3` only on preserved non-IR-014 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-015 media breadth, relay ACL, criteria/live harness, iOS/live proof, UI, notification, or adjacent replay-row closure is claimed. |
| `IR-015` | Covered | IR-015 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-015-plan.md`. `group_media_mime_policy.dart` now maps `application/octet-stream` to safe media type `file`, and `group_media_mime_policy_test.dart` pins that allowlist entry while keeping missing, wildcard, dangerous, and unsupported MIME values rejected. `drain_group_offline_inbox_use_case_test.dart` adds `IR-015 replay rehydrates text quote image video file GIF and voice after live duplicate`, proving one live-plus-replay row, quote target preservation, key epoch, and image/video/file/GIF/voice media descriptor rehydration. `group_resume_recovery_test.dart` adds `IR-015 fake-network replay drains text quote image video file GIF and voice uniformly`, proving Bob's offline replay drains every variant exactly once across repeat drains while Charlie remains live. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, and `group_multi_party_device_criteria_test.dart` add the `ir015` scenario, live proof, and validation rejection cases. Evidence passed: focused MIME policy (`+5`), direct IR-015 (`+1`), fake-network IR-015 (`+1`), criteria IR-015 (`+3`), runner scenario discovery, scoped analyzer, media/quote/IR-014 preservation selectors, Dart format, iOS 26.2 `ir015` proof run `1779171554812` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir015_jcVFVS`. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+217 -3` only on preserved non-IR-015 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-016 retention cutoff, dispatcher overflow replay, restart freshness, hidden outer-id dedupe, relay ACL, UI, notification, Android, physical iOS, macOS app-peer, or adjacent replay-row closure is claimed. |
| `IR-016` | Covered | IR-016 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-016-plan.md`. Production retention cutoff support was already present in `group_backlog_retention_policy.dart`, `drain_group_offline_inbox_use_case.dart`, `group_backlog_retention_notice.dart`, `group_conversation_screen.dart`, and `group_list_screen.dart`, so production code stayed unchanged. `drain_group_offline_inbox_use_case_test.dart` adds `IR-016 long offline cutoff keeps retained backlog and records incomplete history`, proving expired pages are skipped, retained pages persist, explicit expired/retained timestamps are recorded, and cursor progression remains durable. `group_resume_recovery_test.dart` row-names/strengthens the mixed-window fake-network selector with backdated group/member fixture state. `group_conversation_screen_test.dart` and `group_list_screen_test.dart` row-name the expired and mixed-window retention notice/card selectors. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, and `group_multi_party_device_criteria_test.dart` add the `ir016` scenario, `ir016RetentionCutoffProof`, and rejection cases for silent-complete Bob proof and expired-message resurrection. Evidence passed: focused direct IR-016 (`+1`), fake-network IR-016 (`+1`), conversation UI IR-016 (`+2`), list UI IR-016 (`+2`), criteria IR-016 (`+3` after sequential rerun), runner discovery, scoped analyzer, format, diff hygiene, affected IR-015/retention preservation selectors, iOS 26.2 `ir016` proof run `1779173791340` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir016_nIGT2C`. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+217 -3` only on preserved non-IR-016 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-017 dispatcher overflow replay, restart freshness, hidden outer-id dedupe, relay ACL, notification, Android, physical iOS, macOS app-peer, or adjacent replay-row closure is claimed. |
| `IR-017` | Covered | IR-017 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-017-plan.md`. Production dispatcher-overflow recovery behavior was already present through the accepted DE-012 path in `group_message_listener.dart`, `main.dart`, and `group_test_user.dart`, and native dispatcher support was already present through `TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery`, so production and Go code stayed unchanged. `group_message_listener_test.dart` adds `IR-017 dispatcher overflow diagnostic names replay recovery reason`, proving a `group:dispatcher_overflow` diagnostic for `lastEvent == group_message:received` invokes one recovery and preserves overflow state, dropped count, queue depth, max queue size, and message-event reason details in requested/done flow events. `group_resume_recovery_test.dart` adds `IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event`, proving Bob misses live delivery while unsubscribed, overflow-triggered replay restores the stored inbox message exactly once, and a second overflow-triggered drain does not duplicate it. Evidence passed: focused listener IR-017 (`+1`), fake-network IR-017 (`+1`), supporting native overflow diagnostic selector, DE-012 listener/fake-network/bridge/native preservation, scoped analyzer, format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+218 -3` only on preserved non-IR-017 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-016 retention cutoff, IR-018 restart freshness, IR-019 hidden outer-id dedupe, OB-006 observability, relay architecture, simulator/device proof, 3-party E2E, notification, Android, physical iOS, macOS app-peer, or adjacent replay-row closure is claimed. |
| `IR-018` | Covered | IR-018 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-018-plan.md`. `group_recovery_gate.dart` exposes observable active recovery depth, `group_conversation_wired.dart` listens to it, and `group_conversation_screen.dart` renders `group-recovery-banner` plus the loading shell while recovery is active instead of claiming an empty group is current. `group_conversation_screen_test.dart` adds `IR-018 shows recovering state instead of current empty state during replay catch-up` and `IR-018 keeps visible messages live while marking the group as recovering`. `group_conversation_wired_test.dart` adds `IR-018 shows recovery state while restart replay is pending and live messages still arrive`. `handle_app_resumed_group_recovery_test.dart` adds `IR-018 recovery gate stays active until pending replay drain completes`. `group_startup_rejoin_smoke_test.dart` adds `IR-018 restart recovery keeps recovering state until replay drains and live stays active`. Evidence passed: focused IR-018 selector bundle (`+5`), loading-shell preservation selectors (`+2`), lifecycle BB-012 preservation (`+3`), startup GL-018 preservation (`+1`), resume GR-016 preservation (`+1`), scoped analyzer with only pre-existing nonfatal infos/warnings, Dart format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+219 -3` only on preserved non-IR-018 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-016 retention cutoff, IR-017 dispatcher overflow replay, IR-019 hidden outer-id dedupe, IR-020 local history deletion policy, notification, relay architecture, simulator/device proof, 3-party E2E, Android, physical iOS, macOS app-peer, or adjacent replay-row closure is claimed. |
| `IR-019` | Covered | IR-019 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-019-plan.md`. Production behavior stayed untouched because current main already decrypts signed replay envelopes from relay messages shaped as `from`/`message`/`timestamp`, extracts `payload['messageId']`, and dedupes by that id. `drain_group_offline_inbox_use_case_test.dart` adds `IR-019 decrypts hidden payload message id for inbox dedupe`, proving direct offline drain dedupes a hidden-id replay against trusted local content and advances the cursor. `group_resume_recovery_test.dart` adds helper support for omitting the envelope-level message id plus `IR-019 fake-network replay dedupes by decrypted payload id without outer id`, proving fake-network live-plus-replay exact-once recipient state and no duplicate listener/UI row. Evidence passed: focused direct IR-019 (`+1`), focused fake-network IR-019 (`+1`), DE-004 direct/fake-network preservation (`+1` each), GP-026 preservation (`+1`), IR-017 preservation (`+1`), scoped analyzer (`No issues found!`), Dart format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+220 -3` only on preserved non-IR-019 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`). No IR-016 retention cutoff, IR-017 dispatcher overflow replay, IR-018 restart freshness, IR-020 deletion policy, relay architecture, notification, simulator/device proof, or adjacent replay-row closure is claimed. |
| `IR-020` | Covered | IR-020 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-IR-020-plan.md`. `069_group_message_local_deletions.dart` adds a durable local-deletion tombstone table after main's existing `068_removed_group_member_snapshots` migration; `group_message_local_deletions_db_helpers.dart`, `group_messages_db_helpers.dart`, `main.dart`, and `in_memory_group_message_repository.dart` record local deletes and skip replay saves for tombstoned ids while preserving main's removal-cutoff filtering. `069_group_message_local_deletions_test.dart` proves migration schema/idempotency. `group_message_repository_impl_test.dart` proves deleting an unread group message writes a tombstone and replay save cannot resurrect the row or unread count. `drain_group_offline_inbox_use_case_test.dart` proves direct inbox drain and history repair cannot resurrect locally deleted ids. `group_resume_recovery_test.dart` proves fake-network replay after local deletion leaves no row, unread count, or thread summary message. Evidence passed: focused IR-020 migration (`+2`), repository (`+1`), direct drain/history repair (`+1`), fake-network (`+1`), full migration chain (`+7`), IR-019/DE-004/GP-026/GI-034/repeated-drain/listener preservation selectors, scoped analyzer (`No issues found!`), Dart format, and diff hygiene. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+221 -3` only on preserved non-IR-020 residuals `BB-007`, `BB-012`, and `GM-029`; the sampled drain follow-up invariant remains red in unchanged listener/drain retained-history behavior (`GROUP_MESSAGE_LISTENER_SELF_REMOVED_HISTORY_RETAINED` while the selector expects delete-group cleanup) and was not rewritten because it is outside IR-020's local per-message deletion contract. Completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`). No relay retention, remote delete-for-everyone, media/reaction deletion policy, notification, simulator/device proof, or adjacent replay-row closure is claimed. |
| `RA-001` | Covered | RA-001 was skipped as already present during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-001-plan.md`. No code, test, criteria, script, harness, fixture, or helper deltas were imported because current main already has equivalent/stronger coverage. COMPLETE_1 GM-007 proves the M0/M1..M3/M4 history boundary: Bob receives all active-member messages, Charlie receives only pre-removal and post-readd messages, removed-window plaintext count is zero, and all roles converge on the current epoch. GM-006 proves immediate re-add current-epoch behavior, Charlie post-readd publish acceptance, and post-readd bidirectional/future delivery. Current worktree-to-main IR-005 records a fresh iOS 26.2 `gm007` proof run `1779161721700` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Evidence passed in current main: GM-006 host selector (`+1`), GM-007/IR-005/KE-018 host selector (`+1`), GM-006 criteria selector (`+5`), GM-007 criteria selector (`+8`), and scoped analyzer (`No issues found!`). No RA-001 marker, `ra001CanonicalReaddProof`, duplicate scenario, RA-002+ coverage, production behavior, notification, Android, physical iOS, or adjacent-row closure is claimed. |
| `RA-002` | Covered | RA-002 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-002-plan.md`. `group_membership_smoke_test.dart` adds `RA-002 online subscribed removed member is re-added without restart`, proving Charlie remains online/subscribed during removal, sees zero removed-window plaintext, is re-added without restart, receives Alice/Bob post-readd traffic, and publishes after re-add. `group_multi_party_device_real_harness.dart` emits `ra002OnlineSubscribedReaddProof` for Alice, Bob, and Charlie in `private_readd_current`; `group_multi_party_device_criteria.dart` validates that proof; `group_multi_party_device_criteria_test.dart` adds fixture fields and missing/leak negative checks. Evidence passed: focused RA-002 host selector (`+1`), focused `private_readd_current` criteria selector (`+15`), GM-016/GM-017/GM-018/IR-005 GM-007 KE-018/GM-019/GM-024 preservation selectors, scoped analyzer (`No issues found!`), iOS 26.2 `private_readd_current` live proof run `1779181396891` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_dPRI1j`. Broad `groups` remains red at `+222 -3` only on preserved non-RA-002 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`). No production behavior, RA-001 canonical proof, RA-003+ remove/re-add rows, runner changes, notification, Android, physical iOS, or adjacent-row closure is claimed. |
| `RA-003` | Covered | RA-003 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-003-plan.md`. Production code stayed untouched. `group_membership_smoke_test.dart` adds `RA-003 offline removed member resolves removal before readd and receives only post-readd`, proving Charlie is offline during removal and removed-window send, reconnects before re-add, resolves removal, receives only Alice/Bob post-readd traffic, and publishes after re-add. `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add the `private_offline_readd` scenario, `ra003OfflineReaddProof`, proof validation, positive criteria fixture, and missing/leak rejection cases. Evidence passed: focused RA-003 host selector (`+1`), focused `offline_readd` criteria selector (`+3`), runner scenario discovery, GE-006 and affected preservation selectors, scoped analyzer (`No issues found!`), iOS 26.2 `private_offline_readd` live proof run `1779184279659` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_readd_l6RN7b`. Broad `groups` remains red at `+223 -3` only on preserved non-RA-003 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`). No production behavior, RA-004+ remove/re-add rows, stale-invite/remove/key-downgrade paths, notification, Android, physical iOS, or adjacent-row closure is claimed. |
| `RA-004` | Covered | RA-004 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-004-plan.md`. Production code stayed untouched. `accept_pending_group_invite_use_case_test.dart` adds `RA-004 revoked old invite cannot create stale membership before current re-add invite succeeds`; `invite_round_trip_test.dart` adds `RA-004 IJ003 revoked old invite stays rejected before current re-add succeeds`; `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, and `group_multi_party_device_real_harness.dart` add `ra004StaleInviteBeforeReaddProof`, validation, fixtures, negative criteria checks, and old-accept-before-current coordination on the existing `private_stale_invite_readd` scenario. Evidence passed: focused RA-004 application selector (`+1`), focused RA-004 round-trip selector (`+1`), focused RA-004 criteria selector (`+3`), focused `private_stale_invite_readd` criteria selector (`+7`), ML-019/KE-016 preservation selectors, GM-021 preservation selector, runner discovery, scoped analyzer (`No issues found!`), iOS 26.2 `private_stale_invite_readd` live proof run `1779185770100` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_invite_readd_RTqRQd`. The proof recorded old invite epoch `1`, current accepted epoch `2`, old accept before current rejected as `notFound`, stale accept rejected as `revoked`, no stale group/key creation, no key downgrade, and removed-window plaintext count `0`. Broad `groups` remains red at `+223 -4` only on preserved non-RA-004 residuals `BB-007`, `BB-012`, accepted-row `IR-018` fixed-date replay fixture aging past the seven-day retention window, and `GM-029`; completeness-check remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`). No production behavior, RA-005+ remove/re-add rows, ML-019/KE-016 rewrites, BB-007/BB-012/IR-018/GM-029 repairs, notification, Android, physical iOS, or adjacent-row closure is claimed. |
| `RA-006` | Covered | RA-006 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-006-plan.md`. Production code stayed untouched; the existing KE-011 stale-old-key-after-readd listener and fake-network selectors now carry `RA-006 KE-011`, `private_readd_current` emits `ra006DelayedOldKeyAfterReaddProof` beside the KE-011 proof, and criteria tests cover RA-006 valid, missing-proof, and Charlie-downgrade verdicts. |
| `RA-007` | Covered | RA-007 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-007-plan.md`. Production code stayed untouched; `FakeGroupPubSubNetwork` held-delivery controls now resolve both literal peer ids and device ids, `group_membership_smoke_test.dart` adds the active Bob observer partition/re-add selector, and `private_readd_current` emits and validates `ra007PartitionedObserverReaddProof` with valid, missing-proof, and Bob non-convergence criteria coverage. |
| `RA-008` | Covered | RA-008 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-008-plan.md`. Production code stayed untouched; `group_membership_smoke_test.dart` adds the partitioned removed-peer selector proving Charlie misses his removal while held, Bob receives removed-window traffic, Charlie rejoins at epoch 2, receives only Alice/Bob post-heal traffic, can publish after heal, and never persists removed-window plaintext. `private_readd_current` emits and validates `ra008PartitionedRemovedReaddProof` with valid, missing-proof, and removed-window leakage criteria coverage. |
| `RA-009` | Covered | RA-009 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-009-plan.md`. Production code stayed untouched; `group_membership_smoke_test.dart` adds the first post-readd publish selector proving Charlie's first current-epoch send reaches Alice immediately, reaches Bob only after Bob processes the held re-add membership update, and persists exactly once for Alice/Bob. `private_readd_current` emits and validates `ra009FirstReaddPublishProof` with valid, missing-proof, and missing-Bob-visibility criteria coverage while preserving existing GM-035 zero-peer fallback coverage as overlap. |
| `RA-010` | Covered | RA-010 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-010-plan.md`. Production code stayed untouched; `group_membership_smoke_test.dart` adds the incoming-before/after-restart selector proving Charlie receives Alice's first post-readd incoming message before listener restart, preserves current group/key/config/member state, and receives Alice's second post-restart incoming message. `private_readd_current` emits and validates `ra010ReaddIncomingRestartProof` with valid, missing-proof, and lost post-restart delivery criteria coverage. |
| `RA-012` | Covered | RA-012 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-012-plan.md`. Production code stayed untouched. `GroupTestUser` can now re-use the same peer while overriding public, private, ML-KEM, and key-package material. `rotate_and_distribute_group_key_use_case_test.dart` and `group_membership_smoke_test.dart` add same-peer rotated-material selectors, and `private_rotated_device_readd` emits and validates `ra012RotatedDeviceReaddProof` with valid, missing-proof, and retained-old-material criteria coverage. |
| `RA-013` | Covered | RA-013 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-013-plan.md`. `handle_incoming_group_message_use_case.dart` resolves a local same-account secondary device by active device transport, rejects account removed-window replay for that local recipient, and treats same-account secondary-device self delivery as local self delivery while preserving current duplicate, self-echo, media, and event-log behavior. `send_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, and `handle_incoming_group_message_use_case_test.dart` add RA-013 direct invite, accept, and receive selectors. `group_membership_smoke_test.dart` adds fake-network same-user phone/tablet re-add coverage. `private_same_user_multi_device_readd` now has runner, live-harness, criteria, and strict `ra013SameUserMultiDeviceReaddProof` positive/weak-proof rejection coverage. No RA-014 stale-epoch, RA-015, RA-017/RA-018, Go/relay internals, UI, notifications, or live simulator proof is claimed. |
| `RA-014` | Covered | RA-014 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-014-plan.md`. `handle_incoming_group_message_use_case.dart` now rejects active re-added sender messages whose positive `keyEpoch` is below the latest local key epoch at/after the current `joinedAt`, emitting `GROUP_HANDLE_INCOMING_MSG_STALE_EPOCH_AFTER_READD_REJECTED` without persisting the stale row. Direct and fake-network selectors prove stale old-key publish rejection plus later current-epoch delivery; `pubsub_delivery_test.go` exposes a row-named RA-014 selector over the existing GL-009 stale raw envelope proof. `private_readd_current` emits and validates `ra014OldKeyPublishAfterReaddProof` with valid, missing-proof, and stale-acceptance criteria coverage. |
| `RA-015` | Covered | RA-015 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-015-plan.md`. `bridge_group_helpers.dart` now propagates successful `group:join` response `note` values into `GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE` diagnostics. Direct Flutter, fake-network, Go bridge, and Go node selectors prove the `ALREADY_JOINED` remove/re-add refresh sends and stores current config/key material including Charlie; `private_readd_current` emits and validates `ra015AlreadyJoinedReaddRefreshProof` with positive, missing-proof, and missing-current-delivery criteria coverage. |
| `RA-016` | Covered | RA-016 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-016-plan.md`. Production code stayed untouched; current main already rejects removed-interval replay after re-add. `drain_group_offline_inbox_use_case_test.dart` adds `RA-016 rejects delayed removed-interval replay returned after re-add`, proving current main's self-joined lower bound skips pre-readd replay windows while post-readd replay persists. `group_messaging_smoke_test.dart` adds `RA-016 removed-interval replay after re-add is rejected while current delivery converges`, proving forced removed-window replay absence and Alice/Bob/Charlie post-readd convergence. `private_readd_current` now emits and validates `ra016RemovedIntervalReplayProof` with positive, missing-proof, removed-window leakage, missing host coverage, missing live delivery, and final-epoch mismatch criteria coverage. |
| `RA-017` | Covered | RA-017 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-017-plan.md`. Production code stayed untouched. `rotate_and_distribute_group_key_use_case_test.dart` adds the direct key-distribution selector proving repeated Charlie churn keeps Bob and Dana targeted while excluding Charlie during removed windows. `send_group_message_use_case_test.dart` adds the direct durable-recipient selector proving Alice/Bob/Dana sends preserve active-recipient inbox targeting across three Charlie churn cycles. `group_messaging_smoke_test.dart` adds the four-member fake-network selector proving Alice, Bob, and Dana keep sending and receiving while Charlie churns and Charlie receives zero removed-window plaintext. `private_readd_active_members` now has runner, live-harness, criteria, and strict `ra017ActiveMemberChurnProof` positive/weak-proof rejection coverage requiring three cycles, explicit Dana coverage, active A/B/D send/receive counters, no removed-window leakage, and final membership/epoch convergence. No RA-018 alternating churn, RA-013 same-user multi-device policy, production source work, Go/relay internals, UI, notifications, or broad live simulator proof is claimed. |
| `RA-018` | Covered | RA-018 host and criteria proof surfaces were imported during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-018-plan.md`; fixture recovery accepted the row after fresh iOS 26.2 live proof run `1779216477110` passed in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_alternating_churn_UMfABf` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`; the previous failed run `1779213742336` remains historical fixture evidence only. Production code stayed untouched. `rotate_and_distribute_group_key_use_case_test.dart` adds the direct key-distribution selector proving alternating Charlie/Dana churn keeps distribution deterministic for active intervals. `send_group_message_use_case_test.dart` adds the direct durable-recipient selector proving rotating senders target exactly active recipients across C/D churn. `group_messaging_smoke_test.dart` adds the four-member fake-network selector proving three C/D alternation cycles with exact active-interval visibility, no inactive sender attempts, no duplicate visible messages, and zero Charlie/Dana removed-window plaintext. `private_readd_alternating_churn` now has runner, live-harness, criteria, strict `ra018AlternatingChurnProof` positive/weak-proof rejection coverage, and accepted live proof requiring C/D churn targets, A/B/C/D active senders/receivers, three cycles, active-interval evidence, no removed-window leakage, no duplicates, no inactive sender attempts, final A/B/C/D membership convergence, final epoch `13`, and epoch convergence. No RA-017 active-member-only proof, RA-013 same-user multi-device policy, production source work, Go/relay internals, UI, notifications, or broad live simulator proof is claimed. |
| `NW-001` | Covered | NW-001 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-001-plan.md`. `group_messaging_smoke_test.dart` adds `NW-001 full-mesh online A/B/C delivery works without relay fallback`, proving Alice/Bob/Charlie each publish once, every non-sender active member receives exactly once, no duplicate visible rows are created, and each send records `topicPeers=2`, `expectedRecipientCount=2`, and `liveFanoutState=full_peers`. `go-mknoon/node/pubsub_delivery_test.go` adds `TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback`, proving direct peerstore full-mesh topology without waiting for relay fallback and requiring each publish peer count `>=2`. `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_full_mesh_online` plus strict `nw001FullMeshProof` validation, rejecting Alice-only proof, missing Bob/Charlie publish proof, missing/partial topic peer counts, missing receiver tuples, duplicate visible messages, and wrong row ids. Evidence passed: scoped analyzer (`No issues found!`), focused fake-network selector (`+1` after one parallel native-assets build race was rerun serially), criteria selector (`+7`), Go direct-topology selector (`ok github.com/mknoon/go-mknoon/node 2.221s`), runner discovery (`private_full_mesh_online`), `git diff --check`, and exact iOS 26.2 live proof run `1779219623746` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_full_mesh_online_ui6Wkx` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. The orchestrator verdict was `private_full_mesh_online verdicts valid for alice, bob, charlie`; role verdicts recorded `rowId=NW-001`, Alice/Bob/Charlie sender coverage, live-only receipt by each non-sender, duplicate visible message count `0`, success-no-peers count `0`, partial-peer publish count `0`, and topic peer counts all `2`. NW-002 relay/circuit routing, partitions, reconnect, lifecycle, UI, notification, media, and broader network rows remain separate. |
| `NW-002` | Covered | NW-002 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-002-plan.md`. `fake_group_pubsub_network.dart` adds route-mode metadata and delivery records; `group_messaging_smoke_test.dart` adds `NW-002 relay-only or circuit-routed peer receives group messages`, proving Alice-to-Bob and Bob publish-back delivery across relay-only/circuit-routed roles without duplicate visible messages or membership mutation. `go-mknoon/node/pubsub.go` emits sanitized `peerIdPrefix` on group discovery route diagnostics, and `pubsub_delivery_test.go` adds `TestNW002RelayOnlyOrCircuitRoutedPeerReceivesGroupMessages` plus route-diagnostic assertions. `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_relay_only_delivery` and strict `nw002RelayOnlyDeliveryProof` validation, rejecting direct-only/fabricated route proof, missing relay-only role, missing routed receiver/publish-back coverage, success-no-peers without replay proof, duplicate visible delivery, and membership mutation. Evidence passed: scoped analyzer (`No issues found!`), focused fake-network selector (`+1`), criteria selector (`+8`), Go relay/circuit selector bundle (`ok github.com/mknoon/go-mknoon/node 1.688s`), runner discovery (`private_relay_only_delivery`), and iOS 26.2 live proof run `1779221526301` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_only_delivery_ZTdoSK` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. The orchestrator verdict was `private_relay_only_delivery verdicts valid for alice, bob, charlie`; Charlie's role verdict recorded `rowId=NW-002`, `relayOnlyRoles=['bob']`, `circuitOrRelayRouteProven=true`, `directPathSuppressed=true`, Bob-targeted diagnostics `peerIdPrefix=12D3KooWGwRy`, `path=relay`, `attemptedDirect=false`, `directAddrCount=0`, Alice-to-Bob and Bob publish-back live delivery, duplicate visible message count `0`, membership mutation count `0`, and active membership preserved. NW-003 partition healing, NW-004 reconnect repair, broader relay architecture, lifecycle, UI, notification, media, Android, and physical iOS rows remain separate. |
| `NW-003` | Covered | NW-003 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-003-plan.md`. `handle_app_resumed.dart` passes `selfPeerId` into group offline inbox draining; `send_group_message_use_case_test.dart` adds `NW-003 zero-peer removed-window durable send targets Bob but excludes Charlie during partitioned churn`; `group_membership_smoke_test.dart` adds `NW-003 Bob and Charlie partitioned from Alice during remove readd heal to latest state`; `group_resume_recovery_test.dart` adds `NW-003 partitioned removal re-add drains Bob entitled backlog and filters Charlie removed-window before live heal`; and `go-mknoon/node/pubsub_delivery_test.go` adds `TestNW003PartitionDuringRemoveReaddHealsToLatestTopicState`. `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_partition_readd_heal` and strict `nw003PartitionReaddHealProof` validation, rejecting missing row id, fake-only partition coverage, missing Alice-to-Bob or Alice-to-Charlie partition proof, missing Bob removed-window history, Charlie receiving removed-window history, missing final membership/key convergence, and missing post-heal delivery. Evidence passed: scoped analyzer (only pre-existing `handle_app_resumed.dart` style infos), focused durable-recipient selector (`+1`), membership smoke selector (`+1`), resume-recovery selector (`+1`), criteria selector (`+9`), Go partition/re-add selector bundle (`ok github.com/mknoon/go-mknoon/node 3.844s`), runner discovery (`private_partition_readd_heal`), post-run stale-process check, `git diff --check`, and iOS 26.2 live proof run `1779223496207` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_partition_readd_heal_IrYeIA` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. The orchestrator verdict was `private_partition_readd_heal verdicts valid for alice, bob, charlie`; role verdicts recorded `rowId=NW-003`, app-peer iOS 26.2 proof, `fakeNetworkOnly=false`, Alice partitioned from Bob and Charlie, Bob and Charlie partitioned from Alice, removed-window live delivery blocked during partition, Bob received the removed-window after heal, Charlie did not receive it, final Alice/Bob/Charlie membership and key epoch convergence at epoch `2`, and post-heal live delivery from Alice, Bob, and Charlie. NW-004 reconnect repair, NW-005 rediscovery, NW-006 disconnect semantics, broader relay architecture, UI, notification, media, Android, and physical iOS rows remain separate. |
| `NW-004` | Covered | NW-004 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-004-plan.md`. `handle_app_resumed_group_recovery_test.dart` adds the relay reconnect resume-ordering selector; `p2p_service_impl_test.dart` adds the `needsGroupRecovery` propagation selector; `pending_message_retrier_test.dart` adds recovery ordering and no-ack-on-drain-failure selectors; `group_resume_recovery_test.dart` adds reconnect topic repair plus replay drain coverage; `group_startup_rejoin_smoke_test.dart` adds reconnect recovery live-after-ack coverage; `go-mknoon/node/node_test.go` and `go-mknoon/node/relay_session_test.go` add NW-004 relay reconnect/topic-state and watchdog selectors. `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_relay_reconnect_group_recovery` and strict `nw004RelayReconnectRecoveryProof` validation, rejecting missing row id, missing relay drop/reconnect, missing topic rejoin, missing replay drain, missing post-reconnect live delivery, missing recovered-peer publish-back, missing final membership/key convergence, and duplicate visible delivery. Evidence passed: scoped analyzer with only pre-existing style infos in `handle_app_resumed.dart` and `p2p_service_impl.dart`, focused lifecycle selector (`+1`), P2P service selector (`+1`), pending retrier selectors (`+2`), resume-recovery selector (`+1`), startup-rejoin selector (`+1`), criteria selector (`+7`), Go selector bundle (`ok github.com/mknoon/go-mknoon/node 21.366s`), overlap preservation checks for GL-017, GL-018, GR-015, GR-016, NW-001, NW-002, and NW-003, runner discovery (`private_relay_reconnect_group_recovery`), post-run stale-process check, `git diff --check`, and iOS 26.2 live proof run `1779225612219` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_reconnect_group_recovery_sy6Dnj` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. The orchestrator verdict was `private_relay_reconnect_group_recovery verdicts valid for alice, bob, charlie`; role verdicts recorded `rowId=NW-004`, forced relay drop, relay reconnect, Bob `needsGroupRecoveryObserved=true`, group topics rejoined after reconnect, group replay drain completed, missed-during-drop replay recovery, post-reconnect live delivery, recovered peer publish-back live, recovery ack after rejoin and drain on Bob, unchanged membership, final Alice/Bob/Charlie membership and key epoch convergence, and duplicate visible message count `0`. NW-005 rediscovery, NW-006 disconnect semantics, broader relay architecture, UI, notification, media, Android, and physical iOS rows remain separate. |
| `NW-005` | Covered | NW-005 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-005-plan.md`. Production code stayed untouched. `go-mknoon/node/pubsub_test.go` adds `TestNW005RendezvousRediscoveryUsesCurrentMembershipOnly`, proving stale removed peers, fresh unknown peers, and already-connected peers from rendezvous rediscovery are filtered against current group config after remove/re-add churn. `rejoin_group_topics_use_case_test.dart` adds `NW-005 rejoin publishes current membership as discovery authority after churn`, proving Flutter rejoin sends current repository membership/config to native and excludes stale/outsider discovery identities. `group_resume_recovery_test.dart` adds `NW-005 stale and fresh rediscovery subscribers do not change membership truth`, proving stale Charlie and outsider Dana discovery noise cannot mutate membership, cannot receive removed-window plaintext, and do not receive post-readd delivery unless active/current. Evidence passed: Go NW-005 selector (`ok github.com/mknoon/go-mknoon/node 0.589s`), focused Flutter rejoin selector (`+1`), focused fake-network selector (`+1`), Go discovery overlap selector bundle (`ok github.com/mknoon/go-mknoon/node 0.710s`), NW-003/NW-004 resume-recovery preservation selectors (`+1`, `+1`), gofmt, Dart format, scoped analyzer (`No issues found!`), and `git diff --check`. 3-Party E2E is `N/A`, so no simulator/device proof is required or claimed. NW-006 disconnect semantics, NW-008 duplicate connection paths, NW-009 relay probe failures, broader relay architecture, lifecycle, UI, notification, media, Android, and physical iOS rows remain separate. |
| `NW-006` | Covered | NW-006 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-006-plan.md`. `send_group_message_use_case_test.dart` adds `NW-006 disconnected active member remains a durable recipient without delivery receipt claims`, proving a disconnected active Bob remains in Alice's durable recipient set while live fanout stays partial. `handle_app_resumed_group_recovery_test.dart` adds `NW-006 resume recovery keeps disconnected active member state through rejoin and drain`, proving resume repair/drain does not mutate Bob into a removed member. `group_resume_recovery_test.dart` adds `NW-006 peer disconnect does not remove group membership and replay restores the missed message once`, proving Bob misses Alice's disconnected-window send live, recovers it by replay/offline drain, receives post-reconnect live traffic, and publishes back while Alice/Bob/Charlie membership remains stable. `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_peer_disconnect_not_removal` plus strict `nw006DisconnectNotRemovalProof` validation, rejecting missing row id, wrong app-peer source, missing disconnect proof, missing durable-recipient proof, removal side effects, missing replay/live/publish-back proof, duplicate visible delivery, and convergence drift. Evidence passed: scoped analyzers (`No issues found!`), focused criteria selector (`+6`), focused durable-recipient selector (`+1`), focused lifecycle selector (`+1`), focused fake-network selector (`+1`), runner discovery (`private_peer_disconnect_not_removal`), affected NW-004 criteria/lifecycle/fake-network preservation selectors (`+7`, `+1`, `+1`), and iOS 26.2 live proof run `1779228575906` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_peer_disconnect_not_removal_kw0Cuf` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. The orchestrator verdict was `private_peer_disconnect_not_removal verdicts valid for alice, bob, charlie`; role verdicts recorded `rowId=NW-006`, app-peer iOS 26.2 proof, Bob disconnected but still present and active, removed-signal count `0`, membership mutation count `0`, durable recipients including disconnected Bob, missed-disconnect recovery by replay/offline drain, post-reconnect live delivery, Bob publish-back after reconnect, duplicate visible message count `0`, final Alice/Bob/Charlie membership convergence, final key epoch convergence, and stable epoch `1`. The earlier run `1779228190404` remains historical criteria-mismatch evidence after the row-owned harness proof correction. NW-007 topic-peer-zero behavior, NW-008 duplicate connection paths, NW-009 relay probe failures, broader relay shared-state architecture, UI, notification, media, Android, and physical iOS rows remain separate. |
| `NW-007` | Covered | NW-007 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-007-plan.md`. Production code stayed untouched because current main already treats `topicPeers == 0` with successful durable inbox storage as `successNoPeers`, persists the row as sent, and keeps delivery/read receipt claims false. `send_group_message_use_case_test.dart` adds `NW-007 topic peer count zero keeps active member recipients and no receipt claims`, proving active Bob/Charlie remain durable recipients while the sender is excluded and no receipts are claimed. `group_conversation_wired_test.dart` adds `NW-007 zero topic peers keep active member UI and recovery banner`, proving the UI remains writable, keeps all active members verified, preserves the recovery banner, and avoids removed/read-only/pending/error states after a zero-peer send. `handle_app_resumed_group_recovery_test.dart` adds `NW-007 zero topic peers do not disable resume recovery or clear members`, proving rejoin/drain ordering keeps recovery active until drain completes and preserves membership/key state. `group_resume_recovery_test.dart` adds `NW-007 zero topic peers keep membership and replay recovery for all active members`, proving Bob/Charlie recover the zero-peer send after rejoin/drain while Alice/Bob/Charlie membership and key epochs remain stable with no removal signals. Evidence passed: focused NW-007 durable-recipient, UI, lifecycle, and fake-network selectors (`+1` each); affected DE-007/NW-006 send selectors (`+2`); affected generic zero-topic-peer widget selector after an active-member fixture seed (`+1`); affected NW-006 lifecycle selector (`+1`); affected DE-007/NW-006 fake-network selectors (`+2`); Dart format; and scoped analyzer over the three non-widget touched files (`No issues found!`). The full scoped analyzer over all four touched test files remains red only on a pre-existing `_DownloadRepairBridge.mime` unused optional parameter warning in `group_conversation_wired_test.dart:230`, outside NW-007 edits. 3-Party E2E is `N/A`, so no relay env, simulator device, shared dir, run id, Go/native proof, runner, criteria, or live harness proof is required or claimed. NW-008 duplicate connection paths, NW-009 relay probe failures, broader relay shared-state architecture, notification, media, Android, and physical iOS rows remain separate. |
| `NW-008` | Covered | NW-008 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-008-plan.md`. Production code stayed untouched because current main already dedupes incoming group messages by `messageId`, skips duplicate listener stream/notification work when the handler returns `null`, and filters duplicate direct native multiaddrs before group dial. `go-mknoon/node/pubsub_test.go` adds `TestNW008DuplicateConnectionPathsDedupedBeforeGroupDial`, proving duplicate direct addresses collapse to stable unique direct paths and relay-circuit addresses do not survive direct duplicate filtering. `group_message_listener_test.dart` adds `NW-008 duplicate connection path delivery keeps one visible row and status`, proving direct/relay duplicate deliveries with the same message id leave one visible row, one stream emission, one notification, unread count `1`, and delivered status. `group_resume_recovery_test.dart` adds `NW-008 duplicate libp2p-style deliveries keep one visible message per receiver`, proving fake-network duplicate delivery creates one incoming row for Bob and Charlie while the sender row stays sent, unread counts stay `1`, and physical duplicate delivery records are still observable. Evidence passed: focused Go NW-008 selector (`ok github.com/mknoon/go-mknoon/node 0.557s`), focused listener selector (`+1`), focused fake-network selector (`+1`), Go NW-005/GP-013 preservation bundle (`ok github.com/mknoon/go-mknoon/node 0.449s`), affected fake-network NW-005/NW-006/DE-004/DE-005/GP-026 selectors (`+5`), affected listener DE-005 selector (`+1`), gofmt, Dart format, scoped analyzer (`No issues found!`), and `git diff --check`. A broad listener preservation command reproduced the existing notification-count residual outside NW-008 while the row-owned NW-008 and affected DE-005 listener selectors passed. 3-Party E2E is `N/A`, so no relay env, simulator device, shared dir, run id, criteria, runner, or live harness proof is required or claimed. NW-009 relay probe failures, broader relay shared-state architecture, notification repair, media, Android, and physical iOS rows remain separate. |
| `NW-009` | Covered | NW-009 covered during worktree-to-main integration on 2026-05-19 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-009-plan.md`. Production code stayed untouched because current main already keeps relay probe failures as transport-health evidence rather than group membership authority. `go-mknoon/node/relay_session_test.go` adds `TestNW009RelayProbeFailureKeepsReservationHealth`, proving a `NO_RESERVATION` probe/request failure records relay diagnostics but preserves an existing reservation, aggregate online state, `HasReservation`, healthy state, and healthy relay count. `send_group_message_use_case_test.dart` adds `NW-009 relay probe failure keeps active members as durable recipients`, proving a failed `relay:probe` before send does not mutate members, does not remove Bob from durable replay recipients, and does not claim delivery/read receipts from the probe outcome. `group_resume_recovery_test.dart` adds `NW-009 relay probe failure keeps membership and replay recovery active`, proving Bob remains active after the failed probe, misses live delivery while unsubscribed, rejoins, drains replay exactly once, receives later live traffic, and can publish back. Evidence passed: focused Go NW-009 selector (`ok github.com/mknoon/go-mknoon/node 0.571s`), focused send-use-case selector (`+1` after serial rerun of a native-assets startup race), focused fake-network selector (`+1`), Go relay-session preservation bundle (`ok github.com/mknoon/go-mknoon/node 0.414s`), affected send-use-case NW-006/NW-007/GP-005/GP-006/GP-007 selectors (`+5`), affected fake-network NW-006/NW-007/NW-008 selectors (`+3`), affected fake-network DE-004/DE-005/GP-026 selectors (`+3`), gofmt, Dart format, scoped analyzer (`No issues found!`), and `git diff --check`. Smoke and 3-Party E2E are `N/A`, so no relay env, simulator device, shared dir, run id, criteria, runner, or live harness proof is required or claimed. NW-004 reconnect recovery, NW-005 rediscovery, NW-006 generic disconnect semantics, NW-007 zero-topic-peer behavior, NW-008 duplicate connections, broader relay chaos, notification repair, media, Android, and physical iOS rows remain separate. |
| `NW-010` | Covered | NW-010 accepted during worktree-to-main integration recovery on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-010-plan.md`. `drain_group_offline_inbox_use_case_test.dart` adds the direct ordered content-plus-membership drain selector; `handle_app_resumed_group_recovery_test.dart` adds the lifecycle resume/rejoin/drain/ack selector; `group_resume_recovery_test.dart` adds the fake-network background/resume selector; and `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `private_background_resume_group_delivery` plus strict `nw010BackgroundResumeDeliveryProof` validation. Recovery proved the initial Bob blocker was repo-owned in the membership replay recipient path: `GroupInfoWired._onRemoveMember` now stores signed `member_removed` replay for the removed member plus remaining non-self members, `group_info_wired_test.dart` extends the EK004 proof to require Bob in `recipientPeerIds`, and the NW-010 live harness writes `alice_sent_memberRemovedCharlie` proof. Focused evidence passed: production EK004 recipient selector (`+1`), direct drain (`+1`), lifecycle (`+1`), fake-network (`+1`), criteria (`+5`), membership replay preservation selectors (`+2`, `+1`, `+1`), runner discovery, Dart format, scoped analyzer (`No issues found!`), and `git diff --check`. Required iOS 26.2 live proof run `1779235764233` passed in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_srfZDU` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict was `private_background_resume_group_delivery verdicts valid for alice, bob, charlie`. `alice_sent_memberRemovedCharlie` records removed Charlie plus Bob in `recipientPeerIds`; Bob's verdict records ordered drain keys `aliceDuringBackgroundBeforeEdit`, `memberRemovedCharlie`, and `aliceDuringBackgroundAfterEdit`, Alice/Bob-only final membership, final key convergence, recovery ack after rejoin/drain, post-foreground live delivery, publish-back, and duplicate visible message count `0`. Earlier failed runs `1779233091696`, `1779233760981`, and diagnostic run `1779235186050` remain historical blocker evidence. NW-011/NW-012/NW-014 remain separate row-scoped validations. |
| `NW-011` | Covered | NW-011 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-011-plan.md`. The import added only five row-owned host selectors across existing test files: `NW-011 route unmount during group send leaves durable or retryable row, never hidden` in `group_conversation_wired_bg_task_test.dart`; `NW-011 send pre-persist survives lifecycle cancellation window` in `send_group_message_use_case_test.dart`; `NW-011 pause transitions in-flight group send to retryable failed without deleting custody` in `handle_app_paused_group_test.dart`; `NW-011 resume retries failed or pending background send after rejoin and drain` in `handle_app_resumed_group_recovery_test.dart`; and `NW-011 backgrounded sender send is delivered or remains retryable with no invisible send` in `group_resume_recovery_test.dart`. Evidence passed: `flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart --plain-name 'NW-011'`; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-011'`; `flutter test --no-pub test/core/lifecycle/handle_app_paused_group_test.dart --plain-name 'NW-011'`; `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-011'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-011'`; scoped `dart format --set-exit-if-changed` over the five touched files with 0 changed; scoped `flutter analyze` over the five touched files with no issues; and `git diff --check`. Controller affected preservation checks also passed for `GR-017`, both `NW-010` resume/fake-network selectors, and both `NW-007` direct/fake-network selectors before NW-012 selection. No production, native, harness, source-doc, or COMPLETE_1 edits are claimed. 3-Party E2E is `N/A`, so no iOS proof is required for this row. |
| `NW-012` | Covered | NW-012 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-012-plan.md`. Production code stayed untouched; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` was already dirty from prior work and intentionally not edited because expected-recipient decrypt, durable synthetic cursor behavior, and current replay guards were already present. The row-owned import/proof surfaces were the six focused selector files (`drain_group_offline_inbox_use_case_test.dart`, `send_group_message_use_case_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, `handle_app_resumed_group_recovery_test.dart`, `group_resume_recovery_test.dart`, and `group_multi_party_device_criteria_test.dart`), plus `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`. Evidence passed: all six focused `--plain-name 'NW-012'` selectors; preservation selectors for `NW-003|NW-010`, `RA-016|KE-018|NW-010|mixed epoch`, `NW-003|NW-006|NW-007|RA-018`, `RA-018|KE-021`, and `KE-007|KE-009|ML-012`; runner discovery for `private_long_offline_epoch_churn`; scoped format rerun with 0 changes after formatting `integration_test/scripts/group_multi_party_device_criteria.dart`; scoped `flutter analyze` with no issues; and `git diff --check`. Required iOS 26.2 live proof run `1779239961594` passed with `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict `[ORCH] private_long_offline_epoch_churn proof passed: private_long_offline_epoch_churn verdicts valid for alice, bob, charlie`; role verdicts were `gmp_1779239961594_alice_verdict.json`, `gmp_1779239961594_bob_verdict.json`, and `gmp_1779239961594_charlie_verdict.json` in that shared dir. Red residuals are classified non-NW-012: fixed-date replay preservation selectors `GI-022`, `GK-024`, and `GI-023` now age before the 2026-05-20 retention cutoff while `KE-021` passes, `groups` isolates pre-existing `GM-029` role convergence, and `completeness-check` remains on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. NW-013+, KE-007, KE-009, ML-012, broader relay, notification, media, Android, and physical iOS rows remain separate. |
| `NW-013` | Covered | NW-013 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-013-plan.md`. The import added durable pending rotation draft behavior under migration `070_group_key_rotation_drafts`: helper/repository draft APIs, rotate-and-distribute reuse of generated uncommitted key material after restart, committed-key lookup isolation, and in-memory fake support. Evidence passed: focused migration/helper/repository/use-case/fake-network NW-013 tests, KE-013/KE-015/KE-020 preservation selectors, full migration chain, row-owned `dart format --set-exit-if-changed`, row-owned `flutter analyze`, row-owned `git diff --check`, controller spot-check format with 0 changed, controller spot-check diff check, and use-case `--plain-name 'NW-013'` (`+2`). Broad `groups` remains red at `+245 -9` on non-NW-013 residuals `BB-007`, `BB-012`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, plus isolated out-of-scope `NW-004 reconnect recovery stays live after ack across multiple groups`; completeness-check remains red on known unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. Host-only proof; 3-Party E2E is `N/A`; no iOS 26.2/live proof is required or claimed. NW-014+, KE-007, KE-009, ML-012, broader relay, UI, notification, media, privacy, Android, and physical iOS rows remain separate. |
| `NW-014` | Covered - `blocked_external_fixture` | NW-014 row-owned host and harness coverage was imported during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-014-plan.md`, but the row is not fully covered by current live proof because it is closed as `blocked_external_fixture`. `group_messaging_smoke_test.dart` adds `NW-014 deterministic network chaos run maintains model invariants`; `run_group_multi_party_device_real.dart` lists and runs `private_network_chaos_invariants`; `group_multi_party_device_real_harness.dart` emits only `nw014ChaosInvariantProof`; `group_multi_party_device_criteria.dart` validates that proof; and `group_multi_party_device_criteria_test.dart` adds focused NW-014 criteria acceptance/rejection while preserving RA-018. Evidence passed: row-owned format, fake-network selector (`+1`), criteria selector (`+3`), RA-018 preservation criteria (`+1`), scenario discovery, scoped analyzer, ST-proof-field absence check for `st001ModelOracleProof`, `st013RelayChaosProof`, and `st014SoakProof`, and scoped diff hygiene. Required iOS 26.2 live proof run `1779289126608` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_network_chaos_invariants_AJx7Lo` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76` produced no orchestrator verdict: Bob timed out in the existing `_runRa018Bob` key-epoch wait path, and Dana timed out waiting for Alice's cycle-3 Charlie-removal signal after discovery/relay dial failures. Broad `groups` and `completeness-check` reds are classified non-NW-014 residuals. NW-015+, ST proof rows, source docs, COMPLETE_1 docs, production, Go/native, UI, notification, media, Android, and physical iOS remain separate. |
| `NW-015` | Covered | NW-015 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-015-plan.md`. The row-owned host proof is `TestNW015ManualDialDisconnectPreservesGroupTopicConfigAndKey` in `go-mknoon/node/pubsub_test.go` plus `NW-015 manual peer dial and disconnect commands preserve group topic state` in `group_messaging_smoke_test.dart` with its bridge-client import. Evidence passed: focused Go `TestNW015`, focused Flutter NW-015 selector, NW-014 fake-network preservation, NW-006 disconnect preservation, native adjacency regex, gofmt, Dart format with controller 0-changed rerun, scoped analyzer, Go diff check over `node/pubsub_test.go`, and scoped row-owned `git diff --check`. Broad `groups` remains red only on non-NW-015 residuals `BB-007`, `IR-003`, `BB-012`, `NW-004`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`; `completeness-check` remains red on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. Host-only proof; 3-Party E2E is `N/A`; no iOS 26.2/live proof is required or claimed. NW-014 remains `blocked_external_fixture`; KE-007 and KE-009 remain `blocked_conflict`; ML-012 remains `blocked_external_fixture`; PL-001+ remain separate. |
| `PL-001` | Covered | PL-001 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-001-plan.md`. `send_group_message_use_case_test.dart` adds `PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads`, proving emoji, RTL text, combining marks, tabs, and multiline body content remain identical in live publish and replay payloads. `group_resume_recovery_test.dart` adds `PL-001 unicode and multiline text survives live delivery and offline replay`, proving live delivery and offline replay preserve the same payload. The PL-001 fake-network selector includes explicit created/joined/sent timestamps so relay millisecond truncation cannot make replay appear pre-join under broad gate concurrency. Evidence passed: Dart format over both row-owned test files, both focused PL-001 selectors, six preservation selectors, scoped analyzer, scoped diff hygiene, controller selector-on-disk checks, controller focused reruns, controller format rerun with 0 changed, and controller analyzer/diff checks. Broad `groups` remains red only on non-PL-001 residuals `BB-007`, `BB-012`, `NW-004`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`; `completeness-check` remains red on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. No production code, harness, scripts, criteria, source docs, COMPLETE_1 docs, or iOS/live proof is claimed. PL-002+ remain separate. |
| `PL-002` | Covered | PL-002 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-002-plan.md`. Production code stayed untouched because current main already accepts media-only messages with empty text. `send_group_message_use_case_test.dart` adds `PL-002 media-only group message accepts empty text and preserves media`; `group_media_fanout_test.dart` adds `PL-002 fake-network media-only message reaches recipients with empty text`; `go-mknoon/bridge/bridge_test.go` adds `TestPL002GroupPublishMediaOnlyAcceptsEmptyText`; and `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add `pl002` with strict `pl002MediaOnlyProof` validation. Evidence passed: focused PL-002 app/fake-network/criteria selectors, Go bridge selector bundle `TestPL002|TestGroupPublish_MediaOnly_AcceptsEmptyText|TestPL003GroupPublishEmptyTextAndNoMediaFailsInvalidInput`, runner discovery, PL-001/DE-003/IR-014 and criteria preservation selectors, scoped format/analyze/diff hygiene, and iOS 26.2 live proof run `1779294075668` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_pl002_nk5AtA` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with verdict `pl002 proof passed: pl002 verdicts valid for alice, bob, charlie`. Broad residuals remain non-PL-002: `BB-007`, `BB-012`, `NW-004`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`; `completeness-check` remains red on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. PL-003+ remain separate. |
| `PL-003` | Covered | PL-003 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-003-plan.md`. `go-mknoon/bridge/bridge.go` now rejects whitespace-only `GroupPublish` content when no media is present with `strings.TrimSpace(params.Text) == "" && len(params.Media) == 0`, while preserving media-only sends. `bridge_test.go` adds `TestPL003GroupPublishEmptyTextAndNoMediaFailsInvalidInput`; `send_group_message_use_case_test.dart` adds `PL-003 empty text without media is rejected before local ghost row or bridge publish`; and `group_messaging_smoke_test.dart` adds `PL-003 empty text without media creates no local or remote ghost row`. Evidence passed: focused PL-003 Go/app/integration selectors, PL-002 app and fake-network preservation, generic empty/whitespace send preservation, media-only bridge preservation, `TestGK029ParseGroupPayloadAcceptsPresentEmptyTextWithTimestamp` parser guard, gofmt, Dart format with 0 changed, scoped analyzer, scoped diff hygiene, `groups` residual classification at `+249 -9`, and `completeness-check` residual classification at `734/735`. 3-Party E2E/Fake Network/Smoke are `N/A`; no simulator/device, harness, scripts, criteria, media rendering, quote, reaction, UI, notification, or broader payload proof is claimed. PL-004+ remain separate. |
| `PL-004` | Covered | PL-004 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-004-plan.md`. `send_group_message_use_case_test.dart` adds `PL-004 quoted message id is preserved in publish inbox and sender row`; `group_resume_recovery_test.dart` adds `PL-004 quote ids survive live replay and re-add visibility boundaries`; `group_conversation_screen_test.dart` adds `PL-004 renders visible quote parents and unavailable fallback for missing parents`; `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart` add and validate `pl004QuoteReaddLiveProof` for `private_readd_current`. Evidence passed: focused PL-004 app/fake-network/widget/criteria selectors, PL-001/PL-002/PL-003/GE-024/IR-015 preservation selectors, scenario discovery, Dart format with 0 changed, scoped analyzer, scoped diff hygiene, and iOS 26.2 live proof run `1779296325622` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_ALxqho` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, with orchestrator verdict `private_readd_current verdicts valid for alice, bob, charlie`. Broad `groups` remained red at `+250 -9` on known non-PL-004 residuals; `completeness-check` remained red at `734/735` on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. PL-005+ remain separate; no media ACL, reaction, notification, privacy, Android, physical iOS, source-doc, or COMPLETE_1 closure is claimed. |
| `PL-005` | Covered | PL-005 accepted during worktree-to-main integration on 2026-05-20 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-PL-005-plan.md`. `group_media_allowed_peers.dart` adds `groupMediaAllowedPeersForMembers`, which builds media upload ACLs from active group member rows by trimming peer ids, dropping blanks, deduping, and preserving membership order. `group_conversation_wired.dart` now uses the helper for ordinary media and voice upload ACLs, and `retry_incomplete_group_uploads_use_case.dart` uses it for retry upload ACLs while preserving durable inbox recipient semantics. `group_media_allowed_peers_test.dart` adds `PL-005 builds media allowedPeers from unique active member rows`; `group_conversation_wired_test.dart` adds ordinary and voice upload ACL selectors; `retry_incomplete_group_uploads_use_case_test.dart` adds retry ACL coverage and updates adjacent retry expectations for sender-inclusive media ACLs; and `group_media_fanout_test.dart` adds fake-network media ACL fanout proof. Evidence passed: scoped Dart format with 0 changed, scoped analyzer with no issues, focused PL-005 selector bundle (`+5`), adjacent retry selectors `reuploads only group upload_pending attachments and uses blobId` and `MD-011 retry excludes a removed member from media ACLs and inbox recipients`, PL-002 and MD-011 fake-network preservation selectors, scoped diff hygiene, broad `groups` residual classification at `+250 -9`, and `completeness-check` residual classification at `735/736`. Host/fake-network-only row; source 3-Party E2E is `N/A`, so no iOS 26.2 simulator/live proof is required or claimed. PL-006+ media privacy/download rows, reactions, notifications, Android, physical iOS, source docs, and COMPLETE_1 closure remain separate. |
| `KE-022` | Covered | KE-022 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-KE-022-plan.md`. `group_pending_key_repair_service.dart` now defines `key_update_apply_failed`; `group_key_update_listener.dart` requests scoped key repair with that reason after native `group:updateKey` failure while preserving the old active key and avoiding failed-epoch save; `main.dart` wires the production listener to `emitGroupKeyRepairRequest`. `group_key_update_listener_test.dart` proves the bridge failure is diagnosed, recovery is requested, and the old key remains active. `group_messaging_smoke_test.dart` proves the same fake-network path creates a pending live-repair placeholder after an epoch-2 receive failure. `group_conversation_screen_test.dart` proves the key-update recovery placeholder is visible as a degraded state without failed-media retry/delete controls. Evidence passed: focused KE-022 selector bundle (`+3`), affected preservation checks (`+15` total across listener, bridge helper/client, message listener, drain, and UI selectors), scoped analyzer (`No issues found!`), format/diff checks, and host-only live-proof N/A classification. Broad `groups` remains red only on preserved non-KE-022 residuals `BB-007`, `BB-012`, and `GM-029`; completeness-check was not rerun because KE-022 added tests to existing files and did not change gate classification. No source fake-network diagnostic helper infrastructure, Go/relay, real-device, criteria, live-harness, schema, media, notification, or adjacent-row closure is claimed. |
| `KE-021` | Covered | KE-021 covered during worktree-to-main integration on 2026-05-18 by `Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-KE-021-plan.md`. Production files stayed untouched because current main already scopes future direct key-update fanout and group inbox recipients to active membership. `rotate_and_distribute_group_key_use_case_test.dart` proves post-removal direct key-update fanout targets only remaining Bob device identities and excludes removed C peer/device/transport IDs while C retains epoch-1 key material. `drain_group_offline_inbox_use_case_test.dart` proves post-removal `group:inboxStore` and persisted `inboxRetryPayload` recipients exclude C, the replay envelope uses epoch 2, missing future key material saves only an undecryptable placeholder, and key-bound stale material does not reveal plaintext. `group_messaging_smoke_test.dart` proves the same direct-key and inbox targeting over `FakeGroupPubSubNetwork` while Bob receives the epoch-2 post-removal message and removed C stays on epoch 1. `member_removal_integration_test.dart` was updated as preservation-only for the current persisted-key restore precondition and restore-before-generate command order. Evidence passed: all three KE-021 selectors, listed preservation selectors, scoped analyzer (`No issues found!`), format/diff checks, and host-only live-proof N/A classification. Broad `groups` and `completeness-check` gates remain red only on preserved non-KE-021 residuals recorded in the integration breakdown. No Go/relay, real-device, 3-party E2E, schema, durable lease, remote arbitration, tombstone/re-add/history-window, UI, notification, IR-006, or adjacent-row closure is claimed. |
| `GI-008` | Covered | GI-008 covered on 2026-05-14 by exact native relay-retry stream cleanup proof. Existing `GroupInboxStore` and `finishStream` already reset failed streams while closing successful streams, so no production runtime change was required. `go-mknoon/node/group_inbox_test.go::TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream` forces a first-relay non-OK response, proves the failed relay stream is reset rather than cleanly closed, then forces a second-relay OK response and proves clean EOF after client close. Passed evidence: gofmt, exact GI-008 Go (`ok node 0.588s`), adjacent GroupInboxStore selector (`ok node 0.464s`), broader node/internal/crypto inbox selector (`ok node 1.124s`, `ok internal 0.273s`, `ok crypto 0.557s`), selected race selector (`ok node 1.770s`), relay-server inbox selector (`ok relay-server 0.797s`), Flutter drain/retry inbox suites (`+92`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GI-010` | Covered | GI-010 covered on 2026-05-14 by exact native cursor retrieve request proof. Existing `GroupInboxRetrieveWithCursorResult` already normalizes `limit <= 0` to `50`, so no production runtime change was required. `go-mknoon/node/group_inbox_test.go::TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor` starts a local fake relay, captures two framed `group_retrieve_cursor` requests, and proves `limit == 0` and `limit == -1` both serialize as relay-visible `limit == 50` while preserving distinct opaque cursors. Passed evidence: gofmt, exact GI-010 Go (`ok node 0.485s`), adjacent cursor retrieve selector (`ok node 0.477s`), broader node/internal/crypto inbox/history selector (`ok node 0.812s`, `ok internal 1.167s`, `ok crypto 0.901s`), selected race selector (`ok node 1.866s`), relay-server inbox selector (`ok relay-server 0.816s`), Flutter drain/retry inbox suites (`+92`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GI-028` | Covered | GI-028 covered on 2026-05-14 by exact native repair-range normalization proof. Existing `NormalizeGroupHistoryRepairRangeRequest` already defaults `Limit <= 0` to `50`, so no production runtime change was required. `go-mknoon/node/group_inbox_test.go::TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50` normalizes valid repair-range requests with `Limit == 0` and `Limit == -1`, proves both become `50`, and proves non-limit group/gap/source/boundary/hash/head fields are unchanged. Passed evidence: gofmt, exact GI-028 Go (`ok node 0.570s`), adjacent repair-range selector (`ok node 0.470s`), broader node/internal/crypto inbox/history selector (`ok node 0.922s`, `ok internal 1.029s`, `ok crypto 0.418s`), selected race selector (`ok node 1.931s`), relay-server inbox selector (`ok relay-server 0.782s`), Flutter drain/retry inbox suites (`+92`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GI-030` | Covered | GI-030 covered on 2026-05-14 by exact native repair-response fallback proof. Existing `GroupHistoryRepairRange` already fills missing response `groupId`, `gapId`, and `sourcePeerId` from normalized request values, so no production runtime change was required. `go-mknoon/node/group_inbox_test.go::TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs` starts a local fake relay, captures the normalized repair request, returns an OK response without those IDs, and proves the final node response fills them from the request while preserving relay `rangeHash`, `headMessageId`, and replay message. Passed evidence: gofmt, exact GI-030 Go (`ok node 0.540s`), adjacent repair-range selector (`ok node 0.517s`), broader node/internal/crypto inbox/history selector (`ok node 0.596s`, `ok internal 0.681s`, `ok crypto 0.999s`), selected race selector (`ok node 1.720s`), relay-server inbox selector (`ok relay-server 0.828s`), Flutter drain/retry inbox suites (`+92`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GI-034` | Covered | GI-034 covered on 2026-05-14 by exact Flutter app offline replay notification and unread-count proof. Existing `GroupMessageListener`, `DrainGroupOfflineInboxUseCase`, `HandleIncomingGroupMessageUseCase`, and `ShowNotificationUseCase` already combine replay routing, messageId dedupe, recent remote-push suppression, and read-state preservation, so no production runtime change was required. `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-034 offline replay suppresses duplicate notifications and preserves unread state` drains signed replay envelopes through the real listener, seeds a recent remote-push marker for one replay, includes a duplicate of that replay plus a distinct replay, proves two persisted incoming rows, exactly one local notification for the distinct replay, unread totals of two, then marks the group read and proves duplicate re-drain does not create rows, listener emissions, notifications, or unread resurrection. Passed evidence: Dart format, exact GI-034 Flutter proof (`+1`), Go inbox/history owner selector (`ok node 0.813s`), relay inbox/dedup owner selector (`ok relay-server 0.781s`), Flutter drain/retry inbox suites (`+93`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GR-001` | Covered | GR-001 covered on 2026-05-14 by exact native not-started refresh proof. Existing `RefreshRelaySession`/`refreshRelaySessionOwned` already return structured not-started failure when the node has not started, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure` calls public `RefreshRelaySession` on a fresh unstarted node, proves `RecoveryMode == "in_place"`, `Success == false`, `ErrorCode == "NOT_STARTED"`, `Reason == "node not started"`, and `ReusedHost == true`, proves no host/start side effects, proves the shared recovery gate clears, and proves a second call returns the same structured failure. Passed evidence: gofmt, exact GR-001 Go (`ok node 0.534s`), adjacent relay recovery selector (`ok node 21.543s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene. |
| `GR-002` | Covered | GR-002 covered on 2026-05-14 by exact native public refresh coalescing proof. Existing `RefreshRelaySession` and `RelaySessionManager.BeginRecovery`/`CompleteRecovery` already share one recovery and stamp the waiter count, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR002ConcurrentRefreshRelaySessionCallsCoalesce` starts a node with fake relay hooks, blocks the first public refresh owner, starts four concurrent public `RefreshRelaySession` callers, proves three coalesced waiters before release, proves all callers receive the same successful `in_place` result with `ReusedHost == true` and `CoalescedRecoveryRequests == 3`, proves only one hook invocation ran, and proves the shared recovery gate clears. Passed evidence: gofmt, exact GR-002 Go (`ok node 0.582s`), adjacent relay recovery selector (`ok node 21.607s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-003` | Covered | GR-003 covered on 2026-05-14 by exact native stalled recovery timeout proof. `go-mknoon/node/relay_session.go` now carries an unexported manager timeout seam that defaults to the existing production `RecoveryWaitTimeout`; no exported API changed. `go-mknoon/node/relay_session_test.go::TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout` shortens the timeout to 20ms, starts a recovery that never completes, coalesces a waiter, proves `RECOVERY_TIMEOUT` and `RecoveryMode == "timeout"`, proves the gate clears, then starts and completes a fresh recovery on a different promise. Passed evidence: gofmt, exact GR-003 Go (`ok node 0.627s`), adjacent relay recovery selector (`ok node 21.944s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-007` | Covered | GR-007 covered on 2026-05-14 by exact native stopped-node acknowledgement proof. Existing `Node.AcknowledgeGroupRecovery` already returns `node not started` before mutating relay-session manager state or emitting acknowledgement events when the node is stopped, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState` seeds pending recovery with `RecordWatchdogRestart`, stops the node, calls public `AcknowledgeGroupRecovery`, proves the error is `node not started`, proves `needsGroupRecovery` remains true and `watchdogRestartCount` remains 1, and proves no acknowledgement event is emitted. Passed evidence: gofmt, exact GR-007 Go (`ok node 0.595s`), adjacent acknowledgement/recovery selector (`ok node 21.520s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-009` | Covered | GR-009 covered on 2026-05-14 by exact native multi-relay watchdog threshold proof. Existing `RelaySessionManager.OnRefreshFailed` already withholds watchdog transition while any reserved relay remains below `WatchdogMaxConsecutiveFailures`, so no production runtime change was required. `go-mknoon/node/relay_session_test.go::TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold` opens two relay reservations, fails relay A below and through threshold while relay B remains reserved with zero failures, proves no `needsGroupRecovery` and no `watchdog_restart`, then fails relay B below threshold and proves no watchdog signal, finally fails relay B through threshold and proves `needsGroupRecovery == true`, aggregate `watchdog_restart`, and matching status fields. Passed evidence: gofmt, exact GR-009 Go (`ok node 0.569s`), adjacent relay recovery selector (`ok node 21.640s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-010` | Covered | GR-010 covered on 2026-05-14 by exact native refresh-success reset proof. Existing `RelaySessionManager.OnRefreshSucceeded` already resets consecutive failures, restores reserved state, clears stale error, and recomputes online aggregate state, so no production runtime change was required. `go-mknoon/node/relay_session_test.go::TestGR010RefreshSuccessResetsFailureCounterAndStaleError` records refresh failures below threshold, proves a non-zero counter and stored last error before success, calls `OnRefreshSucceeded`, then proves counter reset, reserved state, cleared `LastError`, nonzero `LastReservedAt`, no group recovery signal, online aggregate/status state, healthy count 1, and no stale relay `lastError` in status. Passed evidence: gofmt, exact GR-010 Go (`ok node 0.469s`), adjacent relay recovery selector (`ok node 21.766s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-011` | Covered | GR-011 covered on 2026-05-14 by exact native relay-connectedness filter proof. Existing `go-mknoon/node/node.go::handleRelayConnectednessChanged` already ignores non-relay peers, and `go-mknoon/node/autorelay_metrics.go::syncRelaySessionFromRuntime` syncs only configured relay peers, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers` configures one relay peer, initializes only that relay session, proves non-relay connectedness creates no relay session, emits no relay-state event, and leaves the configured relay untouched, then proves configured relay connect/disconnect updates only that relay's state/status and drops healthy relay count to zero after disconnect. Passed evidence: gofmt, exact GR-011 Go (`ok node 0.545s`), adjacent relay recovery selector (`ok node 21.613s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-012` | Covered | GR-012 covered on 2026-05-14 by exact native stale-circuit health proof. Existing `RelaySessionManager` helpers already make active reservations the source of relay health truth, so no production runtime change was required. `go-mknoon/node/relay_session_test.go::TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation` initializes a relay without reservation, supplies a host-reported `/p2p-circuit` address, and proves stale detection is true, healthy-with-reservation is false, trusted circuit filtering returns empty, status is not online, `healthyRelayCount == 0`, and `lastReservationAt` is absent. It opens a reservation as a positive control, then ends it and proves stale detection/trust filtering/non-online status return. Passed evidence: gofmt, exact GR-012 Go (`ok node 0.967s`), adjacent relay recovery selector (`ok node 21.974s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-013` | Covered | GR-013 covered on 2026-05-14 by exact native foreground recovery budget proof. Existing `refreshRelaySessionOwned` already uses the foreground dial and circuit wait budgets and returns foreground attribution fields, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget` starts a node with a fake relay, captures the warm/wait hook budgets, returns immediate foreground circuit success, and proves successful in-place recovery with `ReusedHost == true`, `ForegroundRecoveryPath == "foreground_success"`, configured foreground timeout/cadence fields, non-negative `RelayWarmMs`, `CircuitAddressWaitMs`, and `RelayRefreshMs`, and warm/wait timings within configured foreground budgets. Passed evidence: gofmt, exact GR-013 Go (`ok node 0.624s`), adjacent relay recovery selector (`ok node 22.169s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-018` | Covered | GR-018 covered on 2026-05-14 by exact native relay recovery event privacy proof. Existing `emitRelayStateEvent`, `syncRelaySessionFromRuntime`, and `StatusFields` already emit bounded relay diagnostics without reading private group content/key state, so no production runtime change was required. `go-mknoon/node/node_test.go::TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe` seeds private group plaintext/key sentinels, triggers relay sync success and watchdog failure event paths, proves success `relay:state` diagnostics include reason, online aggregate state, healthy count, relay peer state, and reservation timestamp, proves failure diagnostics include reason, watchdog aggregate state, group recovery signal, watchdog count, relay peer state, and last error, and recursively proves both event payloads omit sensitive content/key fields and sentinel values. Passed evidence: gofmt, exact GR-018 Go (`ok node 0.542s`), adjacent relay recovery selector (`ok node 21.646s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-019` | Covered | GR-019 covered on 2026-05-14 by exact native group recovery limiter cancellation proof. Existing `acquireGroupRecoverySlot` and `runGroupDiscoveryCycle` already use context-aware slot acquisition plus deferred release, so no production runtime change was required. `go-mknoon/node/pubsub_test.go::TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext` saturates all `GroupDiscoveryConcurrency` recovery slots with discovery hooks blocked on a shared context, proves a queued group cannot acquire a slot before cancellation, cancels the context, proves every active cycle and the queued cycle exit within bounded time, verifies `groupRecoverySem` has no held slots, then runs a fresh recovery with a fresh context and proves it can register/discover and return the slot to zero. Passed evidence: gofmt, exact GR-019 Go (`ok node 0.741s`), adjacent relay/group recovery selector (`ok node 21.636s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GR-020` | Covered | GR-020 covered on 2026-05-14 by exact native AutoRegister preservation proof. Existing `go-mknoon/node/node.go::reconnectRelaysOwned` already suppresses startup auto-registration for the internal restart and restores the caller's original `AutoRegister` value into `lastConfig` before finalizing recovery, while `recoverPersonalRendezvousRegistration` gates personal re-registration on the restored config. `go-mknoon/node/node_test.go::TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting` forces in-place recovery failure into the watchdog full-restart path, covers both `AutoRegister=true` and `AutoRegister=false`, proves `lastConfig.AutoRegister` and namespace are restored in both cases, proves the true case performs initial and watchdog personal registration plus refresh-loop restoration, and proves the false case performs no personal registration and starts no refresh loop. Passed evidence: gofmt, exact GR-020 Go (`ok node 0.751s`), adjacent relay/group recovery selector (`ok node 21.908s`), adjacent Flutter lifecycle/resume pair (`+68`), and diff hygiene passed. |
| `GP-027` | Covered | GP-027 covered on 2026-05-14 by exact wired live-upsert and restart-stable ordering proof. Existing `orderGroupMessagesForTimeline`, repository page loading, and `GroupConversationWired._upsertMessage` already route live and persisted timelines through deterministic timestamp/id ordering, so no production runtime change was required. `test/features/groups/presentation/group_conversation_wired_test.dart::GP-027 out-of-order live messages keep deterministic order after restart` persists and streams a later timestamp before an earlier timestamp, proves the live `GroupConversationScreen` renders earlier then later, disposes/rebuilds the screen against the same repository, and proves restarted load keeps the same order. Passed evidence: Dart format, exact GP-027 widget proof (`+1`), adjacent live-upsert widget selector (`+3`), adjacent repository ordering selector (`+3`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-024` | Covered | GP-024 covered on 2026-05-14 by a narrow native subscription-error classifier and exact row-owned proof. `go-mknoon/node/pubsub.go::shouldLogGroupSubscriptionError` is wired into `handleGroupSubscription` so canceled contexts, direct `context.Canceled`, and direct `context.DeadlineExceeded` exit quietly, while real non-context subscription failures remain loggable before return. `go-mknoon/node/pubsub_test.go::TestGP024SubscriptionErrorLogsOnlyRealFailures` proves canceled-context shutdown, direct canceled/deadline errors, nil errors, and real subscription failures classify according to contract. Passed evidence: gofmt, exact GP-024 Go (`ok node 0.538s`), adjacent subscription-handler selector (`ok node 17.200s`), broader node/internal/crypto selector (`ok node 17.484s`, `ok internal 0.340s`, `ok crypto 0.926s`), selected race selector (`ok node 18.948s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-020` | Covered | GP-020 covered on 2026-05-14 by exact native all-connected maintenance-cadence proof. `go-mknoon/node/pubsub_test.go::TestGP020AllExpectedConnectedReturnsToMaintenanceCadence` seeds an already-backed-off discovery cadence, advances connected members to all expected peers, and proves the next interval returns to `GroupDiscoveryInterval`, `backingOff == false`, consecutive failures reset to zero, and `GroupDiscoveryWarmRetries` is replenished. The same test proves the zero-expected-member path also uses maintenance cadence without backoff and resets warm retry state. Passed evidence: gofmt, exact GP-020 Go (`ok node 0.616s`), adjacent warm/backoff selector (`ok node 11.056s`), broader node/internal/crypto selector (`ok node 12.188s`, `ok internal 0.300s`, `ok crypto 0.899s`), selected race selector (`ok node 12.271s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-019` | Covered | GP-019 covered on 2026-05-14 by exact native partial-progress backoff-reset proof. `go-mknoon/node/pubsub_test.go::TestGP019DiscoveryBackoffResetsAfterPartialProgress` seeds an already-backed-off discovery cadence with missing expected members, advances connected members from `1` to `2` while expected remains `4`, and proves the next interval resets to `GroupDiscoveryWarmInterval`, `backingOff == false`, consecutive failures reset to zero, and `GroupDiscoveryWarmRetries` is replenished. The test then proves the next no-progress cycle consumes the refreshed warm retry budget instead of immediately backing off again. Passed evidence: gofmt, exact GP-019 Go (`ok node 0.663s`), adjacent warm/backoff selector (`ok node 13.378s`), broader node/internal/crypto selector (`ok node 13.525s`, `ok internal 1.114s`, `ok crypto 0.548s`), selected race selector (`ok node 12.665s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-018` | Covered | GP-018 covered on 2026-05-14 by exact native warm retry cadence proof plus narrow cadence-helper extraction. `go-mknoon/node/pubsub.go::initialGroupDiscoveryCadence` and `nextGroupDiscoveryCadence` expose the existing discovery-loop cadence policy for deterministic proof. `go-mknoon/node/pubsub_test.go::TestGP018WarmRetryCadenceKeepsActiveGroupResponsive` proves partially connected active groups start at `GroupDiscoveryWarmInterval`, stay on warm cadence for `GroupDiscoveryWarmRetries` no-progress cycles, avoid an immediate 30s maintenance gap, then back off from `GroupDiscoveryWarmInterval * 2`; partial progress resets the failure streak and warm retry count. Passed evidence: gofmt, exact GP-018 Go (`ok node 0.493s`), adjacent warm/backoff selector (`ok node 11.407s`), broader node/internal/crypto selector (`ok node 13.306s`, `ok internal 1.570s`, `ok crypto 1.038s`), selected race selector (`ok node 14.474s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-017` | Covered | GP-017 covered on 2026-05-14 by exact native in-flight dial gate proof. `go-mknoon/node/pubsub_test.go::TestGP017InFlightDialGateBlocksOnlyWhileActive` proves an active duplicate discovery-cycle dial is blocked with `retryIn == 0` and `blockedByInFlight == true`, a successful finish clears the gate for an immediate third cycle, and a failed finish clears the active gate while preserving normal cooldown until `groupPeerDialBackoff(1)` expires. Passed evidence: gofmt, exact GP-017 Go (`ok node 0.499s`), adjacent in-flight/backoff selector (`ok node 0.359s`), broader node/internal/crypto selector (`ok node 0.390s`, `ok internal 0.623s`, `ok crypto 0.939s`), selected race selector (`ok node 1.688s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-013` | Covered | GP-013 covered on 2026-05-14 by exact native direct-address preference proof. `go-mknoon/node/pubsub_test.go::TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs` builds a mixed peerstore/candidate set containing a real direct address and a synthetic `/p2p-circuit` relay address for the same peer, proves `collectDirectMultiaddrs` returns only deduped non-circuit addresses, then proves `connectGroupPeerPreferDirect` records `AttemptedDirect`, reports the direct-only address count, succeeds with `Path == direct`, leaves `UsedRelayFallback == false`, and establishes a direct libp2p connection. Passed evidence: gofmt, exact GP-013 Go (`ok node 0.572s`), adjacent direct/relay selector (`ok node 0.418s`), broader node/internal/crypto selector (`ok node 0.435s`, `ok internal 0.894s`, `ok crypto 0.649s`), selected race selector (`ok node 1.792s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-012` | Covered | GP-012 covered on 2026-05-14 by exact native invalid peer ID discovery proof. `go-mknoon/node/pubsub_test.go::TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember` seeds invalid config peer IDs in both the legacy member peer field and active-device `TransportPeerId`, returns one invalid rendezvous peer plus one valid member from rendezvous, runs `discoverAndConnectGroupPeers`, proves `discover_result` reports `totalFound == 2`, `newPeers == 1`, `ignoredNonMembers == 1`, and `ignoredInvalidConfigPeers == 2`, proves the valid member connects, and proves the invalid discovered peer is not imported into the peerstore. Passed evidence: gofmt, exact GP-012 Go (`ok node 0.583s`), adjacent discovery/filter selector (`ok node 3.938s`), broader node/internal/crypto selector (`ok node 3.620s`, `ok internal 1.193s`, `ok crypto 0.934s`), selected race selector (`ok node 3.546s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-009` | Covered | GP-009 covered on 2026-05-14 by exact native relay-readiness discovery proof. `go-mknoon/node/pubsub_delivery_test.go::TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady` joins a private group while node A's `relayReady` channel is still open, observes `pre_relay_direct_dial` before readiness, proves relay dial/register/discover hooks remain at zero before readiness, closes `relayReady`, and then proves known-member relay dial success, `registered`, `discover_result`, and hook order `register:<group namespace>` before a later `discover:<group namespace>`. Passed evidence: gofmt, exact GP-009 Go (`ok node 2.901s`), adjacent discovery selector (`ok node 16.204s`), broader node/internal/crypto selector (`ok node 13.876s`, `ok internal 0.937s`, `ok crypto 0.683s`), selected race selector (`ok node 14.430s`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GP-007` | Covered | GP-007 covered on 2026-05-14 by exact native, app, and integration zero-peer bounded-send proofs. `go-mknoon/node/pubsub_delivery_test.go::TestGP007ZeroPeerPublishUsesBoundedSettleWait` proves a zero-live-peer publish with one expected offline member returns caller id/`peerCount == 0`, completes near `GroupPublishZeroPeerSettleWait`, emits zero-peer publish refresh begin/done diagnostics, and records `settleWaitMs == GroupPublishZeroPeerSettleWait.Milliseconds()`. `test/features/groups/application/send_group_message_use_case_test.dart::GP-007 zero topic peers complete without retry staging and use inbox` proves the app send path completes under one second, returns `successNoPeers`, persists `sent`, records durable inbox custody, clears retry/wire payloads, and emits zero-peer timing/fallback metadata. `test/features/groups/integration/group_resume_recovery_test.dart::GP-007 zero-peer send delegates to inbox without visible delay` proves the GroupTestUser bridge path completes under one second, writes sent/inbox-stored sender state with no retry payload, and drains inbox delivery to the offline recipient exactly once. Passed evidence: gofmt, Dart format, focused GP-007 Go (`ok node 1.111s`), adjacent Go publish/discovery selector (`ok node 17.397s`), broader node/internal/crypto selector (`ok node 15.297s`, `ok internal 0.880s`, `ok crypto 1.152s`), selected race selector (`ok node 3.336s`), exact app proof (`+1`), app zero-peer matrix selector (`+24`), exact integration proof (`+1`), adjacent integration selector (`+2`), `./scripts/run_test_gates.sh groups` (`+160`), and diff hygiene. |
| `GO-005` | Covered | GO-005 covered on 2026-05-14 by exact native validation-rejection diagnostic rate-limit proof. Existing `go-mknoon/node/pubsub.go::logPubSubValidationReject` already keys the rate limit by reason, group id, sender id, and transport peer id and suppresses repeats before log/event/feedback emission during `pubsubAuthorizationRejectDiagnosticWindow`. `go-mknoon/node/pubsub_authorization_forward_test.go::TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport` proves 50 same-key rejects emit one `group:validation_rejected` event and one log, distinct transport/sender/group/reason dimensions emit first diagnostics, repeated same-key `missing_key` spam is deduped, and the original key emits again after the window. Passed evidence: gofmt, exact GO-005 Go (`ok node 0.581s`), adjacent LP-002/GA-026 diagnostics selector (`ok node 0.389s`), selected native race selector (`ok node 97.138s`), Flutter send/drain app-facing gate (`+168`), and diff hygiene. |
| `GO-006` | Covered | GO-006 covered on 2026-05-14 by native discovery diagnostic fields plus exact missing-peer/backoff proof. `go-mknoon/node/pubsub.go` now emits `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff` on `discover_result`, includes `missingPeers` and `backingOff` on publish peer refresh begin/done diagnostics, and emits discovery backoff diagnostics through `emitGroupDiscoveryBackoff` with connected/expected/topic/missing counts, consecutive failures, next interval fields, and warm retry state. `go-mknoon/node/pubsub_test.go::TestGO006DiscoveryEventsExposeMissingPeerCondition` proves a group with one missing expected peer emits `discover_result` with `topicPeers == 0`, `expectedPeers == 1`, `missingPeers == 1`, `backingOff == false`, then proves the backoff event exposes the same missing-peer condition plus cadence fields and `backingOff == true`. Existing `lib/core/bridge/go_bridge_client.dart` already forwards `group:discovery` into app diagnostics. Passed evidence: gofmt, exact GO-006 Go (`ok node 0.554s`), adjacent discovery/backoff selector (`ok node 0.469s`), selected native race selector (`ok node 99.377s`), Flutter send/drain app-facing gate (`+168`), and diff hygiene. |
| `GO-007` | Covered | GO-007 covered on 2026-05-14 by exact native host-connected versus live-topic-peer proof. Existing `go-mknoon/node/pubsub.go` uses `topic.ListPeers` through `liveGroupTopicPeerSet` and `countConnectedGroupMembers`; publish refresh diagnostics expose `topicPeers`, `expectedPeers`, `missingPeers`, and `backingOff`; and `PublishGroupMessage` emits `group:publish_debug.topicPeers`. `go-mknoon/node/pubsub_delivery_test.go::TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer` connects the expected peer at the libp2p host layer without joining it to the group topic, proves host connectedness while live topic peer count remains zero, publishes with `peerCount == 0`, observes publish-refresh `topicPeers == 0`, `expectedPeers == 1`, `missingPeers == 1`, `backingOff == false`, observes `group:publish_debug.topicPeers == 0`, and proves the non-topic peer receives no group message event. Passed evidence: gofmt, exact GO-007 Go (`ok node 2.773s`), adjacent topic-peer/zero-peer/discovery selector (`ok node 5.810s`), selected native race selector (`ok node 98.541s`), Flutter send/drain app-facing gate (`+168`), and diff hygiene. |
| `GO-010` | Covered | GO-010 covered on 2026-05-14 by exact native group goroutine leak proof. `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go::TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines` captures filtered goroutine stack baselines for `handleGroupSubscription`, `groupPeerDiscoveryLoop`, `runGroupDiscoveryCycle`, and `discoverAndConnectGroupPeers`; repeats four join/recovery/publish/leave cycles; proves group runtime state removal after every leave; polls group runtime goroutine stacks back to baseline after every cycle; verifies `groupRecoverySem` has no held slots; confirms all register/discover recovery cycles ran; calls `Stop`; and proves group runtime goroutine counts remain at or below baseline. Passed evidence: gofmt, exact GO-010 Go (`ok node 0.578s`), adjacent lifecycle/recovery selector (`ok node 10.316s`), selected native race selector (`ok node 96.500s`), Flutter send/drain app-facing gate (`+168`), and diff hygiene. |
| `GA-026` | Covered | GA-026 covered on 2026-05-14 by exact native all-reject-reason diagnostic privacy proof. `go-mknoon/node/pubsub_authorization_forward_test.go::TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons` emits diagnostics for `not_v3_envelope`, `invalid_envelope`, `group_mismatch`, `peer_mismatch`, `unknown_group`, `ambiguous_signing_key`, `ambiguous_transport_peer`, `non_member`, `unbound_device`, `unauthorized_writer`, `missing_key`, and `bad_signature_or_epoch`, then proves every `group:validation_rejected` event contains only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`; every hash is the expected 12-character truncated value or `none`; logs use the same hashed identifiers; and logs/events omit raw group IDs, sender IDs, transport/local peer IDs, message IDs, device IDs, key-package IDs, public keys, signatures, ciphertext, nonce, and plaintext markers. Passed evidence: gofmt, focused GA-026 (`ok node 0.541s`), adjacent validator/auth selector (`ok node 54.626s`), broader node/internal/crypto selector (`ok node 54.930s`, `ok internal 0.366s`, `ok crypto 0.975s`), selected race selector (`ok node 1.643s`), `./scripts/run_test_gates.sh groups` (`+159`), and diff hygiene. |
| `GA-018` | Covered | GA-018 covered on 2026-05-14 by exact live Go subscription-path proof. `go-mknoon/node/pubsub_delivery_test.go::TestGA018SameTransportSelfEchoIsSkippedOnce` proves local `PublishGroupMessage` emits a separate `group:publish_debug` event for the explicit message id, proves a non-local raw control envelope reaches the local subscription and emits `group_message:received`, then raw-publishes a valid same-transport self-echo envelope with local `senderTransportPeerId` and proves no duplicate `group_message:received`, decrypt, payload-parse, or validation side effect is emitted. Passed evidence: gofmt, focused GA-018 (`ok node 4.714s`), adjacent transport/device selector (`ok node 55.671s`), broader node/internal/crypto selector (`ok node 60.677s`, `ok internal 1.280s`, `ok crypto 1.024s`), selected race selector (`ok node 59.023s`), `./scripts/run_test_gates.sh groups` (`+159`), and diff hygiene. |
| `GK-032` | Covered | GK-032 covered on 2026-05-13 by exact live encrypted receive proof. `go-mknoon/node/pubsub_delivery_test.go::TestGK032PublishedAtNanoInvalidValuesStillEmitMessageWithoutDeliveryMs` publishes raw valid encrypted group-message envelopes with missing, malformed, overflow-sized, and non-string `publishedAtNano` extras, proves every variant emits `group_message:received` with expected message id/text, and proves `deliveryMs` is omitted for invalid/missing values. Passed evidence: gofmt, focused GK-032 (`ok node 0.619s`), adjacent publish/receive selector (`ok node 1.349s`), broader node/internal/crypto selector (`ok node 1.705s`, `ok internal 0.289s`, `ok crypto 0.922s`), selected race selector (`ok node 3.056s`), `./scripts/run_test_gates.sh groups` (`+159`), and diff hygiene. |
| `GK-031` | Covered | GK-031 covered on 2026-05-13 by exact Go unit and live publish/receive proofs. `go-mknoon/node/pubsub.go::buildGroupMessageExtra` writes the explicit `messageId` after copying opts, and `PublishGroupMessage` returns the explicit id when provided. `go-mknoon/node/pubsub_test.go::TestGK031BuildGroupMessageExtraExplicitMessageIDWins` proves conflicting `opts.messageId` cannot override the explicit id and input opts are not mutated. `go-mknoon/node/pubsub_delivery_test.go::TestGK031PublishGroupMessageExplicitMessageIDWinsOverOptsMessageID` proves live publish returns and delivers the explicit id while preserving unrelated opts. Passed evidence: gofmt, focused GK-031 (`ok node 0.683s`), adjacent publish/message-id selector (`ok node 3.389s`), broader node/internal/crypto selector (`ok node 2.590s`, `ok internal 1.252s`, `ok crypto 0.935s`), selected race selector (`ok node 4.093s`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GK-028` | Covered | GK-028 covered on 2026-05-13 by exact native pure-validator, live raw-publish validator, and Dart offline replay proofs. `go-mknoon/node/pubsub.go` validates with the configured active device key instead of trusting legacy `SenderPublicKey`. `go-mknoon/node/pubsub_test.go::TestGK028ValidateGroupEnvelopeRejectsSenderPublicKeyBypass` proves attacker-key signed traffic carrying attacker `SenderPublicKey` rejects under the configured member key. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK028SenderPublicKeyTamperLiveRawPublishRejectsWithoutPayload` proves the live raw-publish path rejects without payload/decrypt/parse/plaintext or attacker-key attribution side effects. `test/features/groups/application/group_offline_replay_envelope_test.dart::GK-028 decode rejects senderPublicKey tamper before decrypt` proves durable replay rejects sender-key mismatch before decrypt. Passed evidence: gofmt, Dart format, focused Go GK-028 (`ok node 4.071s`), focused Dart GK-028 (`+1`), full offline replay envelope suite (`+3`), scoped analyzer clean, adjacent Go selector (`ok node 22.222s`, `ok internal 0.275s`, `ok crypto 0.891s`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GM-032` | Covered | GM-032 covered on 2026-05-13 by private-chat empty-membership send blocking, authoritative all-members-removed listener closure, exact host proofs, combined owner suite, named groups gate, and diff hygiene. `send_group_message_use_case.dart` now returns `groupDissolved` before `group:publish` or `group:inboxStore` when a `GroupType.chat` group has no active local members, while preserving announcement-channel send semantics. `group_message_listener.dart` now treats authoritative raw `members: []` member-removal snapshots as terminal local closure, preserves history, marks the group dissolved, records the membership watermark, and calls `group:leave`. Exact tests: `dissolve_group_use_case_test.dart::GM-032 dissolved group disables publish and inbox while preserving history`, `send_group_message_use_case_test.dart::GM-032 empty active membership disables publish and inbox`, `group_message_listener_test.dart::GM-032 all-members-removed snapshot dissolves, leaves, and preserves history`, and `group_membership_smoke_test.dart::GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others`. Passed evidence: Dart format, focused GM-032 selectors (`+1` each), full send suite (`+86`), full listener suite (`+107`), combined owner suite (`+253`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GL-020` | Covered | GL-020 covered on 2026-05-13 by exact native many-group recovery limiter drain/no-starvation proof, adjacent native recovery/discovery proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. `go-mknoon/node/pubsub_test.go::TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup` saturates `groupRecoverySem` with `GroupDiscoveryConcurrency` active recovery cycles, queues additional groups plus `gl020-affected-group`, proves no queued cycle starts before a slot is released, then releases the active hooks and proves every group registers/discovers exactly once while `maxActive == GroupDiscoveryConcurrency` and the affected group is not starved. Passed evidence: gofmt, focused GL-020 Go proof (`ok node 0.760s`), adjacent join/leave/update/recovery/discovery Go selector (`ok node 19.205s`), Flutter startup rejoin smoke (`+5`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GL-016` | Covered | GL-016 covered on 2026-05-13 by exact native `GetGroupKeyInfo` clone-mutation proof, adjacent native key/join/publish proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. `go-mknoon/node/pubsub_test.go::TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState` starts a real local node, joins with a generated epoch-1 key, rotates to a generated epoch-2 key, retrieves key info with current/previous epoch and grace deadline, mutates `Key`, `KeyEpoch`, `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` on the returned clone, then retrieves again and proves the internal current key, previous key, epochs, and grace deadline remain unchanged and a fresh pointer is returned. The same test publishes `gl016-clone-message` successfully after clone mutation, proving the internal key was not corrupted. Passed evidence: gofmt, focused GL-016 Go proof (`ok node 0.786s`), adjacent GetGroupKeyInfo/join/update/publish Go selector (`ok node 3.554s`), Flutter startup rejoin smoke (`+5`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GL-010` | Covered | GL-010 covered on 2026-05-13 by exact native unknown-leave no-op proof, adjacent native lifecycle proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. `go-mknoon/node/pubsub_test.go::TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState` starts a real local node, joins `gl010-joined-group`, snapshots the joined group's topic, subscription, config, key, subscription context, and discovery context, calls `LeaveGroupTopic("gl010-unknown-group")`, proves the known-group state pointers are unchanged, proves no unknown-group entries are created in group runtime maps, and publishes `gl010-known-message` successfully to the known group with `peerCount == 0`. Passed evidence: gofmt, focused GL-010 Go proof (`ok node 0.608s`), adjacent join/leave/update/recovery Go selector (`ok node 17.831s`), Flutter startup rejoin smoke (`+5`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GO-012` | Covered | GO-012 covered on 2026-05-13 by deterministic fake-network seed/scheduler hardening, exact fake tests, a five-iteration zero-flake runner, scoped analyzer, and named groups gate. `test/shared/fakes/fake_group_pubsub_network.dart` now accepts a deterministic `randomSeed`, resets the seeded random sequence in `resetCounters()`, and routes publish/reaction/held-delivery waits through an injectable delay scheduler. `test/shared/fakes/fake_group_pubsub_network_test.dart::GO-012 seeded drops and scheduled delays are repeatable` proves two fresh seeded networks produce the same delivered message sequence and scheduled delay list without wall-clock waiting; `::GO-012 resetCounters restores seeded drop sequence` proves reset restores the seeded drop sequence. `scripts/run_group_fake_flake_budget.sh` repeats the exact fake test plus selected GE-017/GE-019/GE-020/restart and resume-recovery fake-network selectors. Passed evidence: Dart format, scoped analyzer with no issues, exact fake test (`+2`), `GO012_REPEAT_COUNT=5 ./scripts/run_group_fake_flake_budget.sh` (`GO-012 fake flake budget passed: 5 iterations, 0 failures`), and `./scripts/run_test_gates.sh groups` (`+159`). Initial runner validation exposed a script selector bug where `--plain-name` matched no pipe-delimited selectors; the runner now uses `--name` and the rerun passed. |
| `GO-009` | Covered | GO-009 covered on 2026-05-13 by a repo-owned lifecycle race fix plus clean selected race detector evidence. The required `go test -race ./node -run 'Group|PubSub|Relay' -count=1` initially failed with races in `TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess`, `TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace`, and `TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart`. `go-mknoon/node/node.go` now uses a per-start `*sync.Once` and captures the current relay-ready channel/once in warm-relay goroutines; `go-mknoon/node/pubsub.go` passes the current relay-ready channel into `groupPeerDiscoveryLoop`. Passed evidence: gofmt, focused failing race selector (`ok node 1.695s`), selected group/pubsub/relay race gate (`ok node 94.663s`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GO-008` | Covered | GO-008 covered on 2026-05-13 by runtime privacy hardening, exact native no-secret diagnostic proof, exact Flutter bridge FLOW redaction proof, exact send/drain privacy proofs, analyzer, selected race gate, and named groups gate. `lib/core/bridge/go_bridge_client.dart` logs `group_message:received` FLOW details as bounded metadata only while preserving full app callback delivery; `lib/core/utils/flow_event_emitter.dart` redacts broader direct and JSON/key-value encoded sensitive fields. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents` proves decrypt, parse, and validation diagnostics/logs omit plaintext, group keys, ciphertext, nonce, signatures, and sender private keys. Bridge/send/drain proofs cover raw FLOW redaction, pending inbox retry privacy, and cursor-error redaction. Passed evidence: gofmt, Dart format, scoped analyzer with no issues, focused Go (`ok node 1.171s`), focused bridge (`+2`), focused send (`+1`), focused drain (`+1`), full bridge (`+73`), full send+drain (`+165`), selected Go race gate (`ok node 94.663s`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GO-004` | Covered | GO-004 covered on 2026-05-13 by exact native wrong-local-key diagnostic/no-secret proof, exact Flutter bridge diagnostic/redaction proof, exact listener live key-repair proof, and named groups gate evidence. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly` publishes a valid signed/encrypted group envelope while the receiver has a wrong local key at the same epoch, observes `group:decryption_failed` with `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, AES-GCM error text, and non-negative `decryptMs`, and proves no plaintext marker, group keys, ciphertext, nonce, signature, sender private key, normal message event, or reaction event leaks. `test/core/bridge/go_bridge_client_test.dart::GO-004 group decryption failure diagnostic reaches repair stream without message callback` and `::GO-004 group diagnostic stream redacts sensitive payload fields` prove diagnostics reach `groupDiagnosticEventStream`, preserve group/sender/epoch metadata, redact plaintext/key/ciphertext/nonce/peer/address/secret fields, and do not invoke group-message delivery. `test/features/groups/application/group_message_listener_test.dart::GO-004 live decryption failure creates repair placeholder and trigger without plaintext delivery` proves a safe pending placeholder, pending repair row, and live diagnostic key-repair request without plaintext/key/ciphertext persistence. Passed evidence: gofmt, Dart format, scoped analyzer exit 0 with one pre-existing info-level lint at `group_message_listener_test.dart:4516:13`, focused Go proof (`ok node 5.845s`), focused bridge (`+2`), focused listener (`+1`), and `./scripts/run_test_gates.sh groups` (`+159`). |
| `GO-003` | Covered | GO-003 covered on 2026-05-13 by native validator feedback, Flutter diagnostic handling, named groups gate, iOS binding rebuild, and required relay-backed three-party proof. `go-mknoon/node/group_validation_feedback.go` adds bounded recipient-to-publisher feedback over `GroupValidationFeedbackProtocol`, `go-mknoon/internal/group_envelope.go` carries top-level `messageId`, and `go-mknoon/node/pubsub.go` sends feedback only for rejected `group_message` envelopes with message ids. `go-mknoon/node/pubsub_delivery_test.go::TestGO003StaleSenderValidationFeedbackReturnsToPublisher` proves stale Charlie traffic is rejected by Alice/Bob, Charlie receives exact `group:publish_validation_rejected` feedback, and no stale plaintext renders. `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, and `lib/features/groups/application/group_message_listener.dart` forward the diagnostic and mark the exact outgoing row `failed` while preserving retry wire-envelope metadata; exact bridge/listener tests passed. `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go003` scenario support. Passed evidence: scoped analyzer clean, focused bridge (`+1`), focused listener (`+1`), focused criteria (`+1`), Go proof (`ok node 5.349s`), `./scripts/ensure_go_ios_bindings.sh`, `./scripts/run_test_gates.sh groups` (`+159`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go003 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go003_71Ln1O`, run id `1778700408366`, final result `go003 proof passed: go003 verdicts valid for alice, bob, charlie`, role verdicts in that dir, and `git diff --check` on owned files plus closure docs passed. |
| `GO-001` | Covered | GO-001 covered on 2026-05-13 by exact app, Go, named gate, and required relay-backed three-party proof. `lib/features/groups/application/send_group_message_use_case.dart` now emits explicit `status`, `topicPeers: 0`, `inboxStored: true`, and `inboxPending: false` details for the success-no-peers flow/timing path while preserving honest durable `sent` status when inbox custody succeeds. `test/features/groups/application/send_group_message_use_case_test.dart::GO-001 zero topic peers exposes durable fallback sender status` proves `successNoPeers`, saved `sent` row, durable inbox recipient set, no retry payload, and the zero-peer flow/timing details. `go-mknoon/node/pubsub_delivery_test.go::TestGO001PublishGroupMessageReportsZeroTopicPeers` proves native publish succeeds with the caller-provided id and `peerCount == 0`. `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go001` scenario support using the zero-live-topic durable fallback proof. Passed evidence: format, scoped analyzer, focused criteria (`+2`), focused app test (`+1`), focused Go proof (`ok node 0.566s`), `./scripts/run_test_gates.sh groups` (`+159`), `flutter devices --machine` availability for the three configured iOS simulators, exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go001 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go001_2Xf4af`, run id `1778696136962`, final result `go001 proof passed: go001 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GO-002` | Covered | GO-002 covered on 2026-05-13 by exact send-use-case proof, retry proof, criteria proof, named groups gate, and required relay-backed three-party proof. `test/features/groups/application/send_group_message_use_case_test.dart::GO-002 publish success with inbox failure stays pending and retryable` proves live PubSub success with `topicPeers == 2` plus forced `group:inboxStore` failure saves and returns a `pending` row with `inboxStored == false`, a retry payload, no wire envelope, preserved durable recipients, and flow/timing details that expose pending inbox-store failure state. `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart::GO-002 retry promotes pending inbox store failure to sent` proves one durable retry stores payload id `go002-pending`, promotes the row to `sent`, sets `inboxStored == true`, clears the retry payload, and emits retry success/timing events. `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go002` scenario support forcing Alice's inbox-store call to fail, rejecting sender verdicts marked reliable before retry, then proving retry promotion and Bob/Charlie convergence. Passed evidence: format, scoped analyzer, focused send-use-case (`+1`), focused retry (`+1`), focused criteria (`+2`), `./scripts/run_test_gates.sh groups` (`+159`), `flutter devices --machine` availability for the three configured iOS simulators, exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go002 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_4BmY76`, run id `1778697742706`, final result `go002 proof passed: go002 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GE-020` | Covered | GE-020 covered on 2026-05-13 by exact deterministic host fake-network long-soak proof plus exact relay-backed three-party `ge020` device proof. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-020 long soak private group with churn preserves convergence` runs fixed seeds `20020`, `20021`, and `20022`, 44 operations per seed, and an A/B/C/D model over sends, offline held delivery, online recovery, relay refresh/rejoin, remove, re-add, inactive sends, key rotation, restart, and duplicate send delivery. The oracle records seed, step, operation, active set, online set, current key epoch, and operation log in failure context, and proves no permanent deaf active member, no entitled message loss after recovery, no removed-window or not-yet-added plaintext, no inactive-send publish/message side effects, active membership/key convergence, no duplicate active member or device rows, and no stranded held-delivery work. Supporting `ge020` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria validates `ge020LongSoakChurnProof` and rejects deaf-member, stranded-queue, and divergence failures. Passed evidence: RED baseline selector exited 79/no tests matched, final format and analyzer on the five GE-020 owner Dart files, focused GE-020 host (`+1`), focused GE-020 criteria (`+2`), named `./scripts/run_test_gates.sh groups` (`+159`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge020 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge020_9KMoiD`, run id `1778694622398`, final result `ge020 proof passed: ge020 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus docs after closure. |
| `GE-016` | Covered | GE-016 covered on 2026-05-14 by exact host concurrent-admin membership mutation proof plus required relay-backed three-party `ge016` device proof. `test/features/groups/integration/group_membership_smoke_test.dart::GE-016 two admins mutate membership concurrently and converge` holds and reorders concurrent admin membership mutations, proves active-peer convergence, and proves removed-member cleanup. `test/shared/fakes/group_test_user.dart` now stamps helper-generated membership payloads with deterministic event versions. Supporting `ge016` criteria/runner/harness coverage lives in `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria proves Alice's stale Charlie removal loses to Bob's newer synthetic Dana add with deterministic winner `bob_add_dana`, final A/B/C convergence, Charlie and Dana present, and role/version agreement. Passed evidence: exact GE-016 host (`+1`), focused criteria (`+2`), full criteria (`+191`), scoped analyzer clean, adjacent group smoke/membership/resume (`+133`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge016 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge016_6ktSvg`, run id `1778727856388`, final result `ge016 proof passed: ge016 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GE-021` | Covered | GE-021 covered on 2026-05-14 by exact host large-group flaky-member proof plus required relay-backed three-party `ge021` device proof. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-021 large group with one flaky member preserves stable delivery` uses an 11-member private group, sends from several stable members, repeatedly holds/releases flaky-member delivery, removes and readds the flaky member, and proves all stable entitled members retain expected messages with no stable delivery loss caused by the flaky peer. Supporting `ge021` criteria/runner/harness coverage lives in `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria proves an 11-member roster with Alice/Bob stable real devices, Charlie as the flaky real device, eight synthetic stable members with generated signing and ML-KEM public material, flaky live leave/rejoin, removal/readd, removed-window exclusion, final roster/epoch convergence, no stable-member miss, no stranded delivery, and no removed-window leak. Passed evidence: exact GE-021 host (`+1`), full criteria (`+193`), scoped analyzer clean, adjacent group smoke/membership/resume (`+134`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge021_npLDuk`, run id `1778730737810`, final result `ge021 proof passed: ge021 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GE-023` | Covered | GE-023 covered on 2026-05-14 by exact host media entitlement proof plus required relay-backed three-party `ge023` device proof. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-023 media attachments in private group through remove/re-add respect entitlement` sends encrypted image media before removal, during Charlie's removed window, and after re-add; proves Alice/Bob/Charlie receive entitled media metadata/content, Charlie never receives or persists removed-window media, sender media stays local/done, and attachment metadata carries content hash and encryption metadata. Supporting `ge023` criteria/runner/harness coverage lives in `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; the harness wires SQL-backed media attachment persistence and decodes recorded durable replay payloads through `decodeInboxMessage`. Passed evidence: exact GE-023 host (`+1`), full criteria (`+195`), scoped analyzer clean, adjacent group smoke/membership/resume (`+135`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge023 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge023_7Y5Mx0`, run id `1778733356540`, final result `ge023 proof passed: ge023 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GE-024` | Covered | GE-024 covered on 2026-05-14 by exact host quoted-reply entitlement proof, exact widget unavailable-parent fallback proof, and required relay-backed three-party `ge024` device proof. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-024 quoted replies across membership boundary preserve entitlement fallback` sends a before-removal parent, removes Charlie, sends a removed-window parent, re-adds Charlie, and proves Bob's replies preserve both quote ids while Charlie resolves only the entitled parent and keeps the removed-window parent unavailable without plaintext leakage. `test/features/groups/presentation/group_conversation_screen_test.dart::GE-024 renders available and unavailable quote parents without crashing` proves available and missing parents render safely. Supporting `ge024` criteria/runner/harness coverage lives in `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria validates sent/received `quotedMessageId` values, Charlie's missing removed-window parent, no removed-window plaintext, final membership, and `noCrashRenderingUnavailableQuote`. Passed evidence: exact GE-024 host (`+1`), exact widget (`+1`), full criteria (`+197`), scoped analyzer clean, adjacent group smoke/membership/resume (`+136`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge024 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge024_vdTEXj`, run id `1778735185620`, final result `ge024 proof passed: ge024 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus closure docs. |
| `GE-018` | Covered | GE-018 covered on 2026-05-13 by exact deterministic Go validator/live-path and Dart durable-replay tamper proofs with no production, simulator, runner, or device-harness changes. `go-mknoon/node/pubsub_test.go::TestGE018SeededEnvelopeFieldTamperingValidatorClassifiesFailClosed` runs fixed seeds `18018`, `18019`, and `18020` over malformed JSON, version/type/group/sender/device/transport/public-key/key-package, ciphertext, nonce, key-epoch, signature, missing-field, and legacy public-key forgery mutations and proves only valid controls accept. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGE018SeededEnvelopeTamperingLivePathNeverRendersPlaintext` proves valid live control render and representative tampered raw-publish no-render/no-plaintext behavior. `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GE-018 seeded offline replay envelope tampering rejects before plaintext render` proves valid replay persists once while replay mutations leave no message, cursor, receipt, or decrypt side effects. The stale GEK003 replay proof in the same Dart file was updated to match the current GE-005 fail-closed rotation contract. Passed evidence: focused GE-018 Go/Dart proofs, adjacent Go tamper selector, focused GEK003, full offline replay suite (`+79`), named `./scripts/run_test_gates.sh groups` (`+157`), full `cd go-mknoon && go test ./...`, gofmt, Dart format, scoped analyzer with only existing info-level notes, and `git diff --check` on owned files plus docs after closure. |
| `GE-019` | Covered | GE-019 covered on 2026-05-13 by exact deterministic host fake-network property proof with no production, Go, simulator, runner, or device-harness changes. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-019 seeded random key rotations preserve access windows` runs fixed seeds `19019`, `19020`, and `19021`, 36 operations per seed, and an A/B/C/D model over guaranteed and random sends, key rotations, removals, re-adds, and inactive sends. The oracle records seed, step, operation, active set, current key epoch, and operation log in failure context, and proves senders and active-at-send recipients persist each modeled plaintext exactly once at the modeled key epoch, peers removed or not yet added at send time never render that plaintext even after later re-add, inactive sends do not publish or mutate local messages, active peers converge on the modeled member set and latest key epoch after every operation, and no duplicate active member/device rows appear. Passed evidence: RED baseline selector exited 79/no tests matched, final `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart`, final `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart` with no issues, focused GE-019 host (`+1`), final named `./scripts/run_test_gates.sh groups` (`+158`), and `git diff --check` on owned files plus docs after closure. |
| `GE-017` | Covered | GE-017 covered on 2026-05-13 by exact deterministic host fake-network property proof with no production, Go, simulator, runner, or device-harness changes. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-017 seeded random membership operations preserve invariants` runs fixed seeds `17017`, `17018`, and `17019`, 30 operations per seed, and an A/B/C/D model over add, remove, re-add, send, inactive send, offline, online, restart, duplicate live delivery, and key rotation. The oracle records seed, step, operation, active set, online set, and operation log in failure context, and proves no non-entitled plaintext, no entitled message loss after held-delivery/final recovery, no duplicate active member or device rows, inactive sends do not publish or mutate local messages, active peers converge on membership/key epoch, and no operation panics. Passed evidence: final `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart`, final `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart` with no issues, focused GE-017 host (`+1`), final named `./scripts/run_test_gates.sh groups` (`+157`), and `git diff --check` on owned files plus docs after closure. |
| `GE-015` | Covered | GE-015 covered on 2026-05-13 by code changes plus exact fake-network host, criteria, full criteria, scoped analyzer, formatting, diff hygiene, contact-picker, group-smoke, and required three-device relay evidence. `lib/features/groups/application/record_group_invite_delivery_attempts.dart` now records pending add/re-add invite fanout as `needsResend` with `invite_fanout_pending_after_membership_update`, and `lib/features/groups/presentation/screens/contact_picker_wired.dart` records that pending status after local member/config mutation while deleting it on rollback if bridge config update fails. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-015 admin restart during add/remove repairs fanout honestly` proves remove-fanout interruption before admin restart, fail-closed key promotion, repair after restart, no removed-window Charlie plaintext, durable invite `needsResend` pending status before repair, final sent status, and active peer convergence. Supporting `ge015` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; `test/features/groups/presentation/contact_picker_wired_test.dart` covers the invite-status hardening. Passed evidence: focused GE-015 host (`+1`), focused criteria (`+4`), full criteria (`+182`), scoped analyzer clean, Dart-only format, full contact-picker suite (`+21`), full group messaging smoke (`+31`), exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge015 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw`, run id `1778685690376`, orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw/gmp_1778685690376_ge015_orchestrator_verdict.json`, final result `ge015 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus plan. |
| `GE-014` | Covered | GE-014 covered on 2026-05-13 by exact fake-network host, criteria, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence with no production changes. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-014 re-added Charlie recovers persisted invite key after restart before topic join` proves Charlie receives and persists the re-add invite/key, restarts before joining the topic, recovers persisted group/member/key state, receives Alice/Bob post-readd messages, and sends after recovery. Supporting `ge014` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria accepts valid restart-recovery verdicts and rejects missing persisted invite/key recovery or missing post-readd delivery proof. Passed evidence: format on the five owned files, focused GE-014 host (`+1`), focused criteria (`+6`), full criteria (`+178`), scoped analyzer clean, exact device command `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge014 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge014_E6ghJG`, run id `1778682492377`, orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge014_E6ghJG/gmp_1778682492377_ge014_orchestrator_verdict.json`, role verdicts for Alice/Bob/Charlie in the same dir, final result `ge014 proof passed: ge014 verdicts valid for alice, bob, charlie`, and `git diff --check` on owned files plus plan. |
| `GE-013` | Covered | GE-013 covered on 2026-05-13 by exact fake-network host, criteria, broader smoke, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-013 revoked Bob sibling device cannot send while B1 remains functional` proves Alice plus logical Bob with B1/B2 active, B2 pre-revoke delivery to Alice/B1, B2-only device revocation while B1 remains active, B2 post-revoke `unauthorized` with no bridge publish/inbox store and no post-revoke B2 plaintext, and B1/Alice post-revoke delivery. Supporting `ge013` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/group_multi_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`; criteria accepts valid device-revocation verdicts and rejects post-revoke B2 plaintext or accepted B2 post-revoke sends. Passed evidence: focused GE-013 host (`+1`), focused criteria (`+3`), full criteria (`+172`), scoped analyzer clean, broader group smoke/membership/resume (`+126`), format, `git diff --check`, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_ypH6Cb`, run id `1778677974482`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob primary `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Bob sibling `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge013 proof passed: ge013 verdicts valid for alice, bob, charlie`. |
| `GE-012` | Covered | GE-012 covered on 2026-05-13 by product/harness fixes plus exact fake-network host, send-use-case, criteria, broader smoke, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. Product group sends now pass the current P2P peer as `senderDeviceId` and `senderTransportPeerId`; GE-012 harness sends use the same binding, and restored Bob sibling starts with a fresh transport identity while preserving logical account identity. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-012 same-user Bob devices exchange without sibling rejection` proves Alice sends to both Bob devices, Bob primary sends to Alice and mirrored sibling, Bob sibling sends to Alice and mirrored primary, no duplicate logical Bob membership row appears, and no sibling rejection occurs. Supporting `ge012` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/group_multi_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: same-key send-use-case proof (`+1`), focused GE-012 host (`+1`), focused criteria (`+3`), full criteria (`+169`), scoped analyzer clean, broader group smoke/membership/resume (`+125`), format, `git diff --check`, targeted trailing-whitespace scan, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge012_j0W7hh`, run id `1778676353899`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob primary `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Bob sibling `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge012 proof passed: ge012 verdicts valid for alice, bob, charlie`. |
| `GE-011` | Covered | GE-011 covered on 2026-05-13 by exact fake-network host, criteria, broader smoke, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-011 partial live topic peers use live plus inbox fallback and dedupe` proves Bob remains a live topic peer while Charlie is off the live topic, Alice sends with `publishTopicPeersOverride: 1`, Alice reports `success`, `topicPeers == 1`, sender status `sent`, durable inbox custody for Bob and Charlie, live delivery only to Bob, Bob dedupes duplicate durable replay after live receipt, Charlie re-joins/drains exactly one durable replay, and all roles converge to A/B/C membership/key state. Supporting `ge011` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-011 host (`+1`), focused criteria (`+3`), full criteria (`+166`), scoped analyzer clean, broader group smoke/membership/resume (`+124`), format, `git diff --check`, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_gfMpyN`, run id `1778673583563`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge011 proof passed: ge011 verdicts valid for alice, bob, charlie`. |
| `GE-010` | Covered | GE-010 covered on 2026-05-13 by exact fake-network host, criteria, broader smoke, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-010 zero live topic peers use durable inbox fallback and receivers recover` proves Bob and Charlie retain group/key/member state while not live topic peers, Alice sends with `publishTopicPeersOverride: 0`, Alice reports `successNoPeers`, `topicPeers == 0`, sender status `sent`, durable inbox custody for Bob and Charlie, no retry payload, and no live publish/delivery, then Bob and Charlie return and each persist the Alice message exactly once through durable replay. Supporting `ge010` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-010 host (`+1`), focused criteria (`+3`), full criteria (`+163`), scoped analyzer clean, broader group smoke/membership/resume (`+123`), format, `git diff --check`, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge010_28Xi9i`, run id `1778672213356`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge010 proof passed: ge010 verdicts valid for alice, bob, charlie`. |
| `GE-009` | Covered | GE-009 covered on 2026-05-13 by exact fake-network host, criteria, broader smoke, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-009 network partition heals after membership mutation and replay converges` proves Charlie is partitioned from live topic delivery while Alice removes and re-adds him, Alice/Bob post-readd sends are durable for Charlie, Charlie heals by topic resubscribe plus inbox replay, Charlie receives exactly the post-readd messages, Charlie's post-heal send reaches Alice/Bob, and all roles converge to the same A/B/C membership, key epoch, and GE-009 timeline. Supporting `ge009` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-009 host (`+1`), focused criteria (`+3`), full criteria (`+160`), scoped analyzer clean, broader group smoke/membership/resume (`+122`), format, diff hygiene, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_HzR9rw`, run id `1778670455217`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge009 proof passed: ge009 verdicts valid for alice, bob, charlie`. |
| `GE-008` | Covered | GE-008 covered on 2026-05-13 by exact host, criteria, broader smoke, scoped analyzer, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-008 simultaneous send storm during remove/re-add keeps entitlement windows exact` proves A/B/C pre-removal storm delivery, Alice/Bob removed-window storm delivery with Charlie excluded, Charlie stale removed-window sends rejected/no-publish, A/B/C post-readd storm delivery, exact active-recipient key sets, no removed-window Charlie plaintext, no duplicate timeline spam, no failed/pending sender state, and final A/B/C membership. Supporting `ge008` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-008 host (`+1`), focused criteria (`+3`), full criteria (`+157`), scoped analyzer clean, broader group smoke/membership/resume (`+121`), and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_8DkrLF`, run id `1778668448619`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge008 proof passed: ge008 verdicts valid for alice, bob, charlie`. |
| `GE-007` | Covered | GE-007 covered on 2026-05-13 by exact host, criteria, broader smoke, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-007 remove/re-add while B offline observer catches up entitled messages` proves Bob is offline through Charlie removal/re-add and post-readd sends, Alice's removed-window message is durable to Bob, Alice and Charlie post-readd messages include Bob, Bob drains exactly `aliceGe007RemovedWindow`, `aliceGe007PostReadd`, and `charlieGe007PostReadd` after reconnect, Bob converges to A/B/C final membership, and Bob's post-catch-up send reaches Alice/Charlie. Supporting `ge007` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-007 host (`+1`), focused criteria (`+3`), full criteria (`+154`), scoped analyzer clean, broader group smoke/membership/resume (`+120`), format, `git diff --check`, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_ayKyo8`, run id `1778666286428`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge007 proof passed: ge007 verdicts valid for alice, bob, charlie`. |
| `GE-006` | Covered | GE-006 covered on 2026-05-13 by exact host, criteria, broad smoke, and required three-device relay evidence. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-006 remove/re-add while C offline catches up post-readd only` proves Charlie is offline through removal/re-add, removed-window traffic is Bob-only, Charlie drains exactly Alice/Bob post-readd messages after reconnect, no removed-window plaintext leaks, and Charlie's post-catch-up send reaches Alice/Bob. Supporting `ge006` criteria/runner/harness coverage lives in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Passed evidence: focused GE-006 host (`+1`), focused criteria (`+3`), full criteria (`+151`), scoped analyzer clean, broader group smoke/membership/resume (`+119`), format, `git diff --check`, and required relay proof with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_yCcSao`, run id `1778663062209`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and verdict `ge006 proof passed: ge006 verdicts valid for alice, bob, charlie`. |
| `GL-001` | Covered | `test/features/groups/application/create_group_use_case_test.dart` now includes `duplicate bridge group id converges to one canonical local create state`, proving two `group:create` bridge calls with the same returned group id/topic/key/epoch converge to one group row, one creator membership, canonical topic persistence, and the latest canonical key. |
| `GL-002` | Covered | GL-002 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-002-plan.md`: `create_group_use_case.dart` signs a canonical `group_created` initial membership payload with creator identity, admin role, joined timestamp, public keys, topic, and initial key epoch, appends it through the group event-log callback, and rolls back group/member/key state if signing or append fails. `create_group_with_members_use_case.dart`, `create_group_picker_wired.dart`, `group_message_listener.dart`, and `main.dart` wire creator private key plus `dbAppendGroupEventLogEntry`; `group_event_log_db_helpers.dart` supplies deterministic canonical payload and durable hash-chain append/load/verify behavior. `create_group_use_case_test.dart` proves persisted creator identity/initial epoch, signed payload/signature evidence, no private-key leakage in the event payload, and rollback on signing or append failure; `group_event_log_db_helpers_test.dart` proves canonical ordering, hash-chain append, idempotent replay, conflict detection, and tamper detection. Verified during closure with `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart` passing `+17`. Execution evidence also records `group_message_listener_test.dart` `+72`, update metadata `+6`, dissolve `+6`, membership smoke `+23`, `./scripts/run_test_gates.sh completeness-check` `697/697`, `./scripts/run_test_gates.sh groups` `+94`, and `git diff --check` passing. The broad application-suite `flutter test --no-pub test/features/groups/application` failure remains non-blocking for GL-002 because it is the preexisting unrelated MD-011 future-media replay case already scoped outside this row. |
| `GL-005` | Covered | GL-005 covered on 2026-04-30 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md`: `create_group_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, `group_invite_listener_test.dart`, `group_list_wired_test.dart`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/bridge/bridge_test.go` now pin trusted-private create payloads, selected-member config/publish/invite fanout, public-preview-shaped invite rejection for unknown/blocked senders, repository-backed list visibility, non-member discovery filtering before dial/use, and raw bridge `GroupCreate` rejection for unsupported public/open `groupType` values. `go-mknoon/bridge/bridge.go` rejects unsupported `groupType` before topic join. Passed evidence: the direct Flutter owner suites including `handle_incoming_group_invite_use_case_test.dart` and `group_membership_smoke_test.dart`, targeted Go node `GL005\|GroupRendezvousNamespace\|GroupTopicAndRendezvousNamespace\|FilterDiscoveredGroupMembers\|DiscoverAndConnectGroupPeers\|GroupDiscovery`, bridge `GroupCreate\|GroupJoinTopic`, `./scripts/run_test_gates.sh groups`, and `git diff --check`. The broad Go node `Group\|PubSub\|Rendezvous` regex failed only the known unrelated LP-006 `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` sender/transport mismatch path. |
| `GL-008` | Covered | GL-008 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-008-plan.md`. `group_key_update_listener.dart` now returns for missing groups with `GROUP_KEY_UPDATE_LISTENER_GROUP_NOT_FOUND` and dissolved groups with `GROUP_KEY_UPDATE_LISTENER_GROUP_DISSOLVED` before `group:updateKey`, event-log append, or key save; `group_key_update_listener_test.dart` proves those missing/dissolved direct key-update paths keep bridge state, event-log state, and stored keys unchanged. `group_message_listener_test.dart` proves old `group_metadata_updated`, `member_added`, `member_role_updated`, and `key_rotated` replay after `group_dissolved` cannot mutate metadata, members, keys, or visible messages, and old system events after local delete do not recreate group/member/key/message rows. Existing dissolve/delete/rejoin/smoke coverage still proves durable dissolve fields, repeated dissolve idempotency, dissolved local cleanup, and dissolved-topic rejoin suppression. Plan-recorded gates passed: `group_key_update_listener_test.dart` `+16`, `group_message_listener_test.dart` `+74`, `dissolve_group_use_case_test.dart` `+6`, `delete_group_and_messages_use_case_test.dart` `+3`, `rejoin_group_topics_use_case_test.dart` `+18`, `group_membership_smoke_test.dart` `+23`, `./scripts/run_test_gates.sh groups` `+94`, `./scripts/run_test_gates.sh completeness-check` `697/697`, and `git diff --check`. |
| `GL-009` | Covered | GL-009 covered on 2026-04-30 by `libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-009-plan.md`. `group_config_payload.dart` owns the canonical metadata actor-event payload, signed-envelope fields, and equivalence checks; `group_info_wired.dart` signs admin metadata edits with `payload.sign` before local persistence, publish, or inbox-store and embeds `actorEvent` without leaking private keys; `group_message_listener.dart` verifies `actorEvent` with `payload.verify` before event-log append, metadata mutation, bridge config sync, or timeline insertion. `group_message_listener_test.dart` proves unsigned, signed-payload mismatch, invalid signature, stale/state-hash tamper, and valid signed metadata paths; `group_info_wired_test.dart` proves signed publish payloads, canonical signed content, no private-key leakage, and signing-failure abort; `update_group_metadata_use_case_test.dart` keeps deterministic `configVersion` and canonical `stateHash` proof; `group_resume_recovery_test.dart` now signs the repeated-metadata recovery fixture and proves final metadata convergence with stale replay ignored. Passed evidence: listener `+77`, wired `+28`, update metadata `+6`, create group `+13`, dissolve `+6`, membership smoke `+23`, full migration chain `+6`, focused metadata convergence `+1` with `payload.sign` and Bob/Charlie `payload.verify`, `./scripts/run_test_gates.sh completeness-check` `697/697`, `./scripts/run_test_gates.sh groups` `+94`, `flutter test --no-pub test/features/groups/integration` `+116`, and scoped `git diff --check`. The plan-recorded broad application failure is unrelated MD-011 future-media replay and non-blocking for GL-009. |
| `LP-001` | Covered | `go-mknoon/node/pubsub_test.go` now includes `TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata`, proving topic names and rendezvous namespaces equal `/mknoon/group/<groupId>` and omit sensitive group name/description strings. `TestJoinGroupTopic_LogOmitsHumanReadableMetadata` proves the join log omits sensitive human-readable metadata after `go-mknoon/node/pubsub.go` removed the prior `config.Name` log field. |
| `LP-002` | Covered | LP-002 covered on 2026-04-30 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-002-plan.md`. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward`, proving a live X-B-C raw PubSub topology rejects stale/removed X on B before accepted/decrypt/parse events and does not forward to C for unauthorized message, reaction, membership, metadata, and key-rotation payloads. The same file adds `TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited`, proving validator reject diagnostics are hashed, privacy-safe, and rate-limited; `go-mknoon/node/pubsub.go` and `go-mknoon/node/node.go` implement those diagnostics without changing validation accept/reject semantics; `go-mknoon/node/pubsub_test.go` keeps `TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward` as pure validator event-family proof. Focused LP-002 Go proof, `go test ./cmd/testpeer -run 'Group\|PubSub\|Rendezvous\|Protocol\|Inbox' -v`, and `git diff --check` passed. App-owned peer scoring remains non-applicable because `go-mknoon/node` has no `WithPeerScore`/`PeerScoreParams`; named Flutter gates were not run because no Dart-visible group behavior or bridge API contract changed. The broad owner command still has unrelated dirty-worktree sender/transport mismatch failures in `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`, outside LP-002. |
| `LP-003` | Covered | LP-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-003-plan.md`. `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` adds `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`, proving with live Go/libp2p PubSub that an exited peer receives pre-exit traffic, calls `LeaveGroupTopic`, loses topic, subscription, subscription context, discovery context, config, and key state, receives no post-exit normal message, reaction, parse-failure, or decrypt-failure events, and fails closed on post-exit message/reaction publish with `group not joined`. Existing `go-mknoon/node/pubsub_test.go` keeps local cleanup coverage in `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` and discovery cancellation coverage in `TestLeaveGroupTopic_CancelsDiscoveryContext`. `leave_group_use_case_test.dart`, `delete_group_and_messages_use_case_test.dart`, and `group_message_listener_test.dart` now pin normal leave, active delete, self-removal/member_removed, replayed `group_dissolved`, and dissolved local-only cleanup without a second `group:leave`; focused offline-inbox replay and `group_membership_smoke_test.dart` keep removed-member cleanup/cutoff behavior green. Closure reruns passed the focused Go proof, the three focused Dart owner files, the focused offline-inbox member_removed rerun, `group_membership_smoke_test.dart`, and `git diff --check`. No LP-003 production code changed. Ban is documented as the current `member_removed` mapping because scoped execution found no first-class group ban surface. Known unrelated caveats remain outside LP-003: full offline inbox still has the MD-011 future-media replay failure, and the broad Go bridge owner slice still has the `TestGroupPublish_ResponseIncludesTopicPeers` peer-mismatch failure; `group-real-network-nightly` was not run because relay env is unset. |
| `LP-006` | Partial | `go-mknoon/node/pubsub_test.go` includes `TestGroupDiscoveryCycle_NoKnownPeersUsesRendezvousFallback`, and the 2026-04-30 targeted proof rerun passed that part of the direct gate. The same direct LP-006 gate now fails `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` with `publish to topic: validation failed` after a sender/transport peer mismatch rejection for `sender=sender-zero`. The row remains partial and is implementation-ready/needs code-and-test repair for the zero-peer safe-send proof, plus real bootstrap relay/device-lab fallback proof for rejoin/send from no useful known peers and the failed-fallback user-safe state. |
| `LP-007` | Partial | `go-mknoon/node/pubsub_test.go` now includes `TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay` and `TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay`, proving relay-visible raw group message and reaction envelopes omit plaintext while decrypting with the group key. `go-mknoon/node/group_inbox_test.go` extends `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope` to prove offline inbox relay requests preserve an encrypted replay envelope without exposing message body, media key, invite token, or history text when the notification preview is safe. The row remains partial because live relay-only delivery convergence plus media metadata, invite, key-update, sync-traffic, and relay-visible capture proof are not directly proven. |
| `LP-011` | Partial | `go-mknoon/node/protocol_version_test.go` now proves chat, inbox/group inbox, rendezvous, and media protocol constants use semver-like `/.../1.0.0` IDs, current chat stream negotiation opens only `ChatProtocol` while an unsupported chat protocol ID is rejected, and group inbox store opens a local relay stream on `InboxProtocol`. Existing `TestGroupTopicValidator_NotV3Envelope` proves non-v3 group PubSub envelopes are rejected. The row remains partial because there is still no full compatible/incompatible negotiation matrix for group sync, invites, media metadata, receipts, and key-exchange streams before state mutation. |
| `LP-013` | Covered | LP-013 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-013-plan.md`. `go-mknoon/node/pubsub_delivery_test.go` now includes `TestLP013DefaultPubSubMessageIdUsesSourceAndSeqnoNotPayloadHash`, `TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId`, and `TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe`, proving default PubSub IDs are source-plus-seqno instead of payload hash, duplicate identical encrypted wire envelopes preserve the application `messageId`, and conflicting duplicate app payloads still keep the same app `messageId` for Dart dedupe. Existing `TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt` remains the same-provided-ID live publish anchor. `test/features/groups/application/group_message_listener_test.dart` now includes `LP013 duplicate PubSub delivery preserves first row and notification state`, proving duplicate app deliveries produce one saved row, one UI stream insertion, one local notification, one unread item, and preserve first trusted text/timestamp/status/key/quoted/media fields. Existing anchors passed: `handle_incoming_group_message_use_case_test.dart` duplicate replay with the same `messageId` ignores conflicting content; `group_resume_recovery_test.dart` same message is not duplicated if both pubsub and group inbox deliver it; `group_edge_cases_smoke_test.dart` duplicate delivery; and `group_notification_dedupe_integration_test.dart` notification dedupe. Verified commands: `cd go-mknoon && go test ./node -run 'TestLP013\|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'`; the focused existing duplicate anchors; `./scripts/run_test_gates.sh groups`; `flutter test --no-pub test/features/groups/integration`; and `git diff --check`. The broad Go owner command failed only known unrelated peer-mismatch tests `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`, with LP-013 tests passing inside that selection. No LP-013 production code changed; relay/device proof is supporting only while relay env is unset, and first-class group receipts remain out of scope because no scoped group receipt protocol exists. |
| `IJ-001` | Covered | IJ-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-001-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, and `lib/features/groups/application/accept_pending_group_invite_use_case.dart`. The implementation adds first-class `GroupInvitePolicy`, embeds `invitePolicy` only inside encrypted invite payload plaintext, keeps cleartext v2 envelopes to preview/routing fields, fails closed for parsing, send preflight, pending-store, direct-handle, materialization, and pending-accept repair, and derives pending expiry from the policy clamped no later than the local TTL. Exact tests: `group_invite_payload_test.dart` includes `IJ001 parses a first-class encrypted invite policy` and `IJ001 rejects missing or contradictory first-class invite policy`; `pending_group_invite_test.dart` includes `IJ001 clamps sender policy expiry no later than local TTL`; `send_group_invite_use_case_test.dart` includes `keeps join material and policy details inside encrypted invite payload` and `IJ001 returns invalidPayload before encryption or delivery when policy derivation fails`; `store_pending_group_invite_use_case_test.dart` includes `IJ001 rejects missing first-class policy before pending or group state` and `IJ001 rejects contradictory policy before pending or group state`; `handle_incoming_group_invite_use_case_test.dart` includes `IJ001 rejects invite missing first-class policy before group state or join` and `IJ001 rejects contradictory policy before group state or join`; `accept_pending_group_invite_use_case_test.dart` includes `IJ001 invalid pending policy stays pending for repair without state or join` and `IJ001 contradictory pending policy stays pending for repair without state or join`; `invite_round_trip_test.dart` proves both `full invite round-trip: admin sends invite -> receiver processes it -> group is persisted` and `GroupInviteListener stores pending invite and explicit accept completes the join flow` preserve the encrypted policy privately; `group_new_member_onboarding_test.dart` remained green for the authorized post-join state/history boundary. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/pending_group_invite_test.dart` failed before production edits because `GroupInvitePolicy`/`invitePolicy` did not exist, then passed after implementation (`+21`); `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed (`+57`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+72`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+12`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+94`); `flutter test --no-pub test/features/groups/integration` passed (`+116`); controller reran `dart format --output=none --set-exit-if-changed` on IJ-001 Dart files, `git diff --check`, and the focused IJ-001 domain/application commands. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Current peer-bound `allowedDevices: [recipientPeerId]` is accepted for IJ-001 only; separate account/device policy remains outside the shipped Peer ID invite contract. Signed inviter auth, revocation, and reuse/replay remain IJ-002, IJ-003, and IJ-005 respectively; auto-join is covered by IJ-009; concurrent joins and history entitlement remain IJ-010 and IJ-011 respectively. |
| `IJ-002` | Covered | IJ-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-002-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, and `lib/features/orbit/presentation/screens/orbit_wired.dart`. Test helper: `test/core/bridge/fake_bridge.dart`. The implementation creates a signed canonical invite attestation before encryption, keeps the signature and policy inside encrypted invite plaintext, verifies receive/listener/direct-accept paths with the trusted contact public key, authorizes the inviter from the signed group snapshot, and revalidates at accept time so tampered, unsigned, unauthorized, invite-disabled, or removed-inviter payloads are rejected before pending/group/key/join/consumption side effects. Exact tests: `group_invite_payload_test.dart` includes `IJ002 requires signed invite attestation and rejects canonical mismatch`; `send_group_invite_use_case_test.dart` includes `IJ002 signs canonical invite payload before encryption and delivery` and `IJ002 returns invalidPayload without encryption or delivery when invite signing fails`; `handle_incoming_group_invite_use_case_test.dart` includes `IJ002 rejects invalid invite signature before group state or join`, `IJ002 rejects tampered signed invite fields before group state or join`, and `IJ002 rejects signed non-admin or removed inviters before state or join`; `group_invite_listener_test.dart` includes `IJ002 does not store pending invite when signature verification fails` and `IJ002 does not store pending invite from unauthorized or removed inviter`; `accept_pending_group_invite_use_case_test.dart` includes `IJ002 tampered persisted signed invite is deleted without state or join` and `IJ002 persisted signed snapshot must still authorize inviter at accept time`; `add_group_member_use_case_test.dart` and `create_group_with_members_use_case_test.dart` remained green for add/create authorization and invite fan-out boundaries; `invite_round_trip_test.dart` and `group_new_member_onboarding_test.dart` remained green for signed invite round trip and authorized onboarding. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` failed at 2026-05-01 02:07 CEST before production edits because invite signatures/signing/verification and accept-time authorization were missing; exact format command passed with `0 changed`; `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart` passed (`+18`); `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` passed (`+69`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+81`); `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart` passed (`+30`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+12`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+94`); `flutter test --no-pub test/features/groups/integration` passed (`+116`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Stale/removed inviter rejection is closed for the self-contained signed snapshot plus accept-time trusted contact revalidation; no durable historical membership-index semantics are claimed. Revocation delivery is covered by IJ-003; direct invite replay/reuse is covered separately by IJ-005; auto-join is covered by IJ-009; concurrent joins are covered by IJ-010; separate account/device registry remains outside the shipped Peer ID invite contract; broad event-family signature parity remains EK-004. |
| `IJ-003` | Covered | IJ-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-003-plan.md`. Production files: `lib/features/groups/domain/models/group_invite_revocation_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/revoke_pending_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/core/services/incoming_message_router.dart`. The implementation adds signed canonical encrypted `group_invite_revocation` payloads, signs before encryption, direct-sends with inbox fallback, validates trusted signer/auth snapshot plus recipient binding, expiry, transport sender, and canonical signature before mutation, then stores a tombstone and deletes only the matching pending invite. Exact tests: `group_invite_revocation_payload_test.dart` covers privacy, tamper, binding, and expiry; `revoke_pending_group_invite_use_case_test.dart` covers sign-before-encrypt direct delivery, inbox fallback, and sender failure paths; `group_invite_listener_test.dart` covers listener dispatch, tombstone storage, pending refresh, and invalid signature fail-closed handling; `store_pending_group_invite_use_case_test.dart` covers delayed direct/mailbox original invite rejection after tombstone; `accept_pending_group_invite_use_case_test.dart` covers revoked accept with no pending/group/key/join/consumed side effects; `incoming_message_router_test.dart` covers router dispatch; `invite_round_trip_test.dart` covers integration-level revoked invite replay rejection. Preservation tests for invite payload, send, handle, and onboarding remained green. Commands relied on: RED `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart` failed before production because the revocation payload/API/router path was missing, then passed after implementation; `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart` passed; `flutter test --no-pub test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` passed; `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed; `flutter test --no-pub test/core/services/incoming_message_router_test.dart`, `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`, `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`, `./scripts/run_test_gates.sh groups`, `flutter test --no-pub test/features/groups/integration`, QA rerun smoke suites, and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. This row does not close TP-SMOKE-01, invite replay/reuse policy, auto-join denial, concurrent joins, richer device binding, or broad event-family signature parity. |
| `IJ-005` | Covered | IJ-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-005-plan.md` for direct signed invite credential reuse/replay. Production files: `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/features/groups/application/accept_pending_group_invite_use_case.dart`. The implementation adds explicit signed/encrypted `singleUse` and `multiUse` reuse policy, defaults direct sends to `singleUse`, supports an explicit `multiUse` direct send path, fails closed for missing/unknown/contradictory reuse policy, checks single-use consumption tombstones and expiry before pending/accept side effects, rejects direct replay to a different peer/device when local identity is available, and keeps multi-use replay idempotent without duplicate local membership, key, join, pending, or duplicate-group side effects. Direct evidence: `group_invite_payload_test.dart`, `send_group_invite_use_case_test.dart`, `store_pending_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `group_invite_listener_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `invite_round_trip_test.dart`, and onboarding/groups integration gates. Commands relied on: RED focused command failed before production because `GroupInviteReusePolicy`, `GroupInvitePolicy.reusePolicy`, and `sendGroupInvite(reusePolicy:)` were missing; focused IJ-005 command passed (`+81`); invite wildcard passed (`+96`) after listener compatibility fix; onboarding passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+96`); `flutter test --no-pub test/features/groups/integration` passed (`+118`); `git diff --check` passed. Supporting `group-real-network-nightly` was unconfigured with `FLUTTER_DEVICE_ID is required for Group Real-Network Nightly Gate.` and is non-blocking. Residual caveats: first-class link invite creation/claim remains prerequisite-owned or product-scope unsupported until a link-token surface exists, and shared account-wide cross-device consumption remains outside the shipped Peer ID invite contract and would require a separate account/device/shared-state model. |
| `IJ-009` | Covered | IJ-009 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-009-plan.md`. Production files: `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, and `lib/main.dart`. The implementation requires a current non-empty local peer id before direct or pending invite resolution, rejects mismatched `recipientPeerId`, rejects invites whose `invitePolicy.allowedDevices` does not contain the local peer id, and wires persisted identity into `GroupInviteListener`; rejection happens before pending invite rows, group rows, member/key state, notifications, or `group:join`. Exact tests: `handle_incoming_group_invite_use_case_test.dart` includes IJ-009 coverage for rejecting signed invites when local peer identity is unavailable before group/key/join state; `store_pending_group_invite_use_case_test.dart` includes IJ-009 coverage for rejecting missing and mismatched local peer identity before pending/group/key/join state; `group_invite_listener_test.dart` includes IJ-009 coverage for copied signed invite rejection and identity-unavailable listener rejection before pending stream, pending row, group/key, notification, or `group:join` state. Preservation tests in `accept_pending_group_invite_use_case_test.dart`, `join_group_use_case_test.dart`, `invite_round_trip_test.dart`, and `group_membership_smoke_test.dart` remained green. Commands relied on: RED focused command `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart` failed before production edits (`+54 -3`), then passed after implementation (`+57`); `dart format --output=none --set-exit-if-changed` on IJ-009 Dart files passed with `Formatted 9 files (0 changed)`; `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart` passed (`+19`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed (`+23`); `./scripts/run_test_gates.sh groups` passed (`+96`); `git diff --check` passed. Supporting `group-real-network-nightly` failed only because `FLUTTER_DEVICE_ID` is unset. First-class link invite creation/claim remains out of scope until a link-token surface exists; first-class shared account/device semantics remain outside the shipped Peer ID invite contract; IJ-010 concurrent join convergence is covered separately; EK-004 broad event-family signature parity remains a separate row; TP-SMOKE-01 remains supporting-only. |
| `IJ-010` | Covered | IJ-010 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-010-plan.md`. `test/features/groups/integration/group_membership_smoke_test.dart` adds `IJ010 concurrent direct invite accepts converge membership epoch and delivery`, proving with the fake-network multi-user harness that an admin and existing member converge after a batch `members_added` authoritative config, Charlie and Dave accept distinct signed direct pending invites concurrently, both joiners issue `group:join` and subscribe only after acceptance, admin/existing/Charlie/Dave converge on exactly the intended peer IDs and roles, all joined participants hold the same latest key epoch and encrypted key material, both pending invite rows clear with consumed tombstones, uninvited Eve has no group/key/subscription/messages, and post-join sends from both joiners are delivered to the existing member and trusted participants. Preservation evidence keeps `invite_round_trip_test.dart` coverage for `concurrent pending accepts converge members, key epoch, and sendability` green. Commands relied on: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010'` passed (`+1`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'concurrent pending accepts converge members, key epoch, and sendability'` passed (`+1`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. The authorized history/state entitlement is covered by IJ-011; separate account/device registry, EK-004 broad event signatures, RP conflict semantics, and first-class real relay/device nightly proof are not closed by IJ-010. |
| `IJ-011` | Covered | IJ-011 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-011-plan.md`. `group_new_member_onboarding_test.dart` now tightens `new member receives current metadata and roles without pre-join history`, proving a newly added member receives the latest metadata, creation fields, membership set, role snapshot, and explicit permission overrides after pre-join metadata and role changes. The test pins Charlie's reader role plus custom `GroupMemberPermissions` (`inviteMembers: false`, `editMetadata: false`, `pinMessages: true`) in Bob's new-member snapshot, verifies Bob's own member row has no custom permission overrides, verifies Bob has no pre-join message/timeline rows before post-join traffic, and verifies a post-join message is delivered while pre-join history remains inaccessible. Existing onboarding tests cover no pre-join text/media backfill, post-join media descriptors/downloads, post-join reactions without pre-join reaction state, quoted pre-join parent fallback, and deterministic add/send boundaries; `invite_round_trip_test.dart` preserves future-only history and post-join replay. Commands relied on: focused IJ-011 onboarding test passed (`+1`); full `group_new_member_onboarding_test.dart` passed (`+6`); `invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. First-class group pinned-message state is not a shipped group-chat surface in this repo, so IJ-011 covers the current pin-related group permission state (`pinMessages`) but does not claim product-level group pinned-item sync. IJ-013 is now covered for shipped Peer ID / `allowedDevices` invite binding and IJ-014 now covers shipped inline group-key repair state; separate account/device registry, RP authorization/conflict rows, EK signatures/key rows, and first-class real relay/device proof remain outside IJ-011. |
| `IJ-012` | Partial | `group_multi_device_convergence_test.dart` now includes `sibling device stays one member while new human admission adds a distinct member`, proving same-peer sibling devices share joined group state without a duplicate human membership row, while a separately invited peer becomes a distinct member across phone, sibling device, existing member, and new member repos and can send after admission. Existing policy and invite tests prove membership/metadata/history are shared only after joined-device materialization and pending invite review is device-local. The row remains partial because self-authenticated sibling-device admission, admin device approval, first-class per-device key packages, and live 3-party/device proof are absent. |
| `IJ-013` | Covered | IJ-013 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-013-plan.md`. `accept_pending_group_invite_use_case.dart` now revalidates persisted pending invites against the current local identity (`senderPeerId`) before reuse checks, signature authorization, materialization, group key persistence, inbox drain, or `group:join` side effects: `recipientPeerId` must match and `invitePolicy.allowedDevices` must contain the local peer id, otherwise the pending row is deleted and `invalidPayload` is returned. `accept_pending_group_invite_use_case_test.dart` adds `IJ013 copied pending invite rejects wrong local identity before state or join`, proving a copied pending invite creates no pending row, consumed tombstone, group, key, message, or `group:join` side effect on the wrong local identity. Existing row-adjacent coverage remains green: `handle_incoming_group_invite_use_case_test.dart` proves matching bound invites accept and v1/v2 wrong-recipient invites reject before state; `store_pending_group_invite_use_case_test.dart` proves missing or mismatched local identity is not stored; `group_invite_listener_test.dart` proves copied signed invites do not enter pending state; `send_group_invite_use_case_test.dart` proves encrypted invite payloads bind `recipientPeerId` and `allowedDevices`. Commands relied on: focused IJ-013 accept-pending test passed (`+1`); handle recipient-peer tests passed (`+3`); store local-identity test passed (`+1`); listener copied-invite test passed (`+1`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+101`); `invite_round_trip_test.dart` passed (`+14`); `group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Current trusted-private invites bind to the shipped local libp2p Peer ID / `allowedDevices` identity unit; IJ-014 now covers shipped inline group-key repair state. IJ-013 does not claim a separate account/device registry, sibling-device approval, EK/RP signatures/authorization rows, TP-SMOKE real-device proof, or first-class real relay/device proof. |
| `IJ-014` | Covered | IJ-014 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-IJ-014-plan.md`. `handle_incoming_group_invite_use_case.dart` now classifies explicit invalid, stale, or undecryptable join-material `BridgeCommandException` failures, rolls back partially materialized group, member, and group-key state, emits `GROUP_INVITE_HANDLE_JOIN_MATERIAL_REPAIR_PENDING`, and returns a repairable invalid-payload outcome instead of clearing the pending invite into an unusable joined group. `accept_pending_group_invite_use_case_test.dart` adds IJ-014 tests proving repairable join-material failure keeps the pending invite row, creates no consumed tombstone, group, member, key, message, publish, mailbox drain, or successful join side effect, and can retry successfully after fresh key material. `handle_incoming_group_invite_use_case_test.dart` proves direct materialization rolls back group/member/key state on a repairable welcome decrypt failure. `group_list_wired_test.dart` proves the pending invite remains visible and the UI shows the fresh key-material warning; full `group_list_wired_test.dart` also keeps valid accept and generic `bridgeError` behavior green. Commands relied on: focused IJ-014 accept tests passed (`+2`); focused IJ-014 direct handler test passed (`+1`); focused IJ-014 UI test passed (`+1`); adjacent UI preservation tests passed (`+2`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+104`); `invite_round_trip_test.dart` passed (`+14`); `group_new_member_onboarding_test.dart` passed (`+6`); full `group_list_wired_test.dart` passed (`+17`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. IJ-014 does not claim first-class MLS welcome/key-package transport, a separate device identity registry, sibling-device approval, live three-party device proof, or first-class real relay/device proof. |
| `RP-002` | Partial | Migration 057 adds durable `permissions_json` storage for group members. `group_members_db_helpers_test.dart`, `057_group_member_permissions_test.dart`, and `group_repository_impl_test.dart` prove helper, migration, and repository persistence of permission overrides. `add_group_member_use_case_test.dart`, `remove_group_member_use_case_test.dart`, `update_group_member_role_use_case_test.dart`, and `rotate_and_distribute_group_key_use_case_test.dart` prove writer-role overrides can grant invite, remove, manage-role, and rotate capabilities while explicit false overrides deny admins. The row remains partial because pin/delete capabilities, receive-side remote enforcement, stale permission races, escalation protection, and live 3-party/device coverage are not directly proven. |
| `RP-003` | Partial | `leave_group_use_case_test.dart` proves a sole admin cannot leave while admin leave succeeds when another admin remains; `update_group_member_role_use_case_test.dart` proves the last admin cannot be demoted while self-demotion succeeds with another admin; `remove_group_member_use_case_test.dart` now proves last-admin removal is blocked before member deletion or bridge sync while removing an admin succeeds when another admin remains. The row remains partial because owner roles, ownership handoff APIs, simultaneous owner-transfer conflict handling, receive-side owner enforcement, and live 3-party/device proof are absent. |
| `RP-004` | Covered | RP-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-004-plan.md`. `GroupKeyUpdateListener` now re-authorizes direct `group_key_update` receive messages by requiring `message.from` to be a current group member with effective `rotateKeys` permission before `group:updateKey`, event-log append, or key save. `group_key_update_listener_test.dart` adds RP004 tests proving an unauthorized writer direct key update is ignored before bridge update, log, or key save while a writer with explicit `rotateKeys` override is accepted; the full listener file remains green. `member_removal_integration_test.dart` now seeds authorized sender membership for direct key-update receive fixtures and passes under the new auth contract. Existing RP-004 evidence remains green: local guards cover add, remove, role update, key rotation, metadata edit, send, send reaction, and remove reaction, while `group_message_listener_test.dart` proves writer-originated receive-side mutation events for `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, and `group_dissolved` leave state and bridge side effects unchanged. Commands relied on: focused RP004 key-update tests passed (`+2`); full `group_key_update_listener_test.dart` passed (`+18`); generic receive mutation guard passed (`+1`); focused local mutation guard tests each passed (`+1`); `member_removal_integration_test.dart` passed (`+5`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`); `git diff --check` passed. The broad `flutter test --no-pub test/features/groups/application` command still fails unrelated existing MD-011 drain-inbox media replay coverage, which also fails in isolation and is not caused by RP-004. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. RP-004 covers shipped role/metadata/key/send/reaction/invite/removal mutation paths; first-class group pin, message edit/delete, and ban product flows are not shipped and are not claimed by this row. |
| `RP-005` | Covered | RP-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-005-plan.md`. `GroupMessageListener` now rechecks current sender membership/role state for receive-side membership and metadata mutation events instead of trusting stored `createdBy` after a creator is demoted or removed. `group_message_listener_test.dart` adds `RP005 demoted creator receive-side mutations are rejected before side effects`, proving demoted creator-originated add, remove, role, and metadata mutation events leave group/member/timeline state unchanged and avoid `payload.verify`/`group:updateConfig` side effects. Existing local stale queued-action guards remain green for add, remove, role update, key rotation, metadata edit, send, and failed-message retry; existing receive stale watermark tests remain green for older metadata and role/member events after newer state. Commands relied on: focused RP005 listener test passed (`+1`); metadata/role watermark tests passed (`+1` each); focused local stale guard tests passed (`+1` each); full `group_message_listener_test.dart` passed (`+81`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). The broad `flutter test --no-pub test/features/groups/application` command still fails unrelated existing MD-011 drain-inbox media replay coverage, and the MD-011 test fails in isolation. Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. RP-005 covers shipped local stale-action rechecks and receive-side stale mutation rejection; broad cryptographic actor-signature proof, first-class real transport/device proof, and unshipped product surfaces remain outside this row. |
| `RP-006` | Covered | RP-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-006-plan.md`. `group_role_update_authorization.dart` now blocks non-admin actors from assigning admin or changing an existing admin role while preserving the existing unheld-permission grant rejection. `update_group_member_role_use_case.dart` now loads the target member before local escalation checks and passes current target role and permissions into the shared helper before mutation or bridge sync. `group_message_listener.dart` uses that helper for receive-side `member_role_updated`, so replayed limited-manager role changes cannot promote to admin, demote or touch an existing admin, or grant unheld permissions before member state, timeline rows, or `group:updateConfig` side effects. Direct evidence: `update_group_member_role_use_case_test.dart` covers local promote denial, admin-demotion denial, and allowed reader-to-writer override; `group_message_listener_test.dart` covers receive-side promote denial, admin-demotion denial, and unheld-permission denial; `drain_group_offline_inbox_use_case_test.dart` self-removal replay fixtures now include the current admin sender membership required by stricter receive-side authorization. Commands relied on: focused RP-006 local and listener tests passed; full `update_group_member_role_use_case_test.dart` passed (`+11`); full `group_message_listener_test.dart` passed (`+82`); focused self-removal replay fixtures passed; `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). Broad `flutter test --no-pub test/features/groups/application --reporter json` still fails only unrelated existing MD-011 future-media replay coverage. Supporting `group-real-network-nightly` was not run because relay/device env is unset. RP-006 does not claim a first-class permission-edit UI/API, broad cryptographic actor-signature matrix, account/device registry, real-device proof, or unshipped pin/delete product surfaces. |
| `RP-010` | Partial | `group_multi_device_convergence_test.dart` now includes `device-local unsubscribe preserves member account and sibling delivery`, proving the existing fake-network device hook can unsubscribe one same-peer sibling device while the shared `peerId` member row remains in every repo and the still-joined sibling continues receiving group traffic. The row remains partial because production membership remains keyed by `(groupId, peerId)`, group members have one ML-KEM key instead of per-device key packages, `rotateAndDistributeGroupKey` distributes by member peer id, and there is no device-removal UI/API, future-key exclusion proof, or live/equivalent 3-party device proof. |
| `RP-011` | Partial | `member_removal_integration_test.dart` proves removal updates the local member set before key rotation and the rotated key is distributed only to remaining members, excluding the removed peer. `invite_round_trip_test.dart` already proves a removed peer can return only through an explicit remove -> rotate -> re-invite flow and then sends on the rotated epoch. The row remains partial because true ban/unban is not implemented: there is no group ban tombstone, ban/unban use case, receive-side ban event, unban policy or surface, banned-invite rejection, or live/equivalent proof that banned identities cannot rejoin or receive future keys. |
| `RP-014` | Covered | RP-014 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-014-plan.md`. `broadcast_voluntary_leave_use_case.dart` now provides a first-class application helper for voluntary leave preparation: it publishes self-removal, stores durable replay only for remaining members, rotates/distributes the next key to remaining members, and fails before `leaveGroup` cleanup if rotation cannot complete while remaining members exist. `group_info_wired.dart` calls the helper before local cleanup. `member_removal_integration_test.dart` extends `voluntary leave rotation excludes leaver and remaining members send on rotated epoch` to prove key-update recipients exclude the leaver, remaining members save/promote epoch 2, `leaveGroup` removes leaver group/member/key state, post-leave send and inbox replay use epoch 2 with recipients excluding the leaver, normal drain skips deleted group state, and a forced post-leave replay attempt persists only `groupUndecryptablePlaceholderText` with `undecryptable` status instead of future plaintext. Commands relied on: focused RP-014 integration test passed (`+1`); focused multi-admin and writer leave UI tests passed (`+1` each); full `group_info_wired_test.dart` passed (`+27`); `group_membership_smoke_test.dart` passed (`+24`); `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`). Supporting `group-real-network-nightly` was not run because relay/device env is unset. RP-014 does not claim configurable leave policy, packet-capture/real-device proof, first-class ban/unban policy, or broader removed-peer dial/publish isolation. |
| `RP-016` | Partial | `invite_round_trip_test.dart` proves a removed peer can rejoin only through explicit direct or inbox-fallback re-invite carrying the rotated epoch, while `group_membership_smoke_test.dart` proves a removed member loses active group/subscription state, misses removed-period traffic and notifications, and resumes only after re-add with current member/key state. The row remains partial because this is removal/re-add policy, not ban policy: no first-class group ban tombstone, ban/unban use case, banned member role, receive-side ban event, unban surface, banned-invite rejection, or live/equivalent ban proof exists. |
| `RP-017` | Covered | RP-017 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-017-plan.md` for the shipped ignore/filter removed-peer isolation policy. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestRP017RemovedPeerContinuedPublishesAreRejectedBeforeAcceptAndForward`, proving a removed peer's raw live message, reaction, membership, metadata, and key-rotation publishes are rejected as non-member traffic before accepted delivery or forwarding. `go-mknoon/node/pubsub_test.go` adds `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate`, proving `UpdateGroupConfig` removal excludes the removed peer from known-member and rendezvous discovery dials while a remaining member stays eligible. Focused Flutter evidence proves removed members cannot send/retry, future media ACLs, inbox recipients, and key updates exclude them, replayed self-removal cuts off later queued traffic, unauthorized `member_removed` is ignored, and future-media replay with only an old epoch saves only an `undecryptable` placeholder with no plaintext, media download, or decrypt. Commands relied on: focused RP-017 Go proof passed; focused membership/media/retry/inbox/key/listener Flutter tests passed; `./scripts/run_test_gates.sh groups` passed (`+97`); `flutter test --no-pub test/features/groups/integration` passed (`+119`); `git diff --check` passed. The shipped policy is ignore/filter rather than forced disconnect or peer downscore; supporting `group-real-network-nightly` was not run because relay/device env is unset. |
| `RP-018` | Covered | RP-018 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-RP-018-plan.md`. `group_message_listener.dart` now applies stale `member_removed` events when the target member still exists from before the removal timestamp, ignores old removals after explicit re-adds, and rejects `member_role_updated` events for missing targets before a stale snapshot can recreate a removed member. `group_message_listener_test.dart` adds `RP018 stale removal beats role replay and later role cannot resurrect`, proving remove-over-role ordering, missing-target role rejection, no extra config update after the target is gone, and diagnostics (`GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_CONFLICT_APPLIED`, `GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATE_MISSING_TARGET_IGNORED`). `group_membership_smoke_test.dart` adds `RP018 partitioned add remove promote demote replay converges membership`, proving fake-network add/remove/promote/demote replay after partition heal converges admin, Bob, Diana, and observer on the same final member/role map while Charlie is removed/unsubscribed. Commands relied on: focused RP-018 listener and smoke tests passed (`+1` each); full `group_message_listener_test.dart` passed (`+83`); full `group_membership_smoke_test.dart` passed (`+25`); resume membership churn and same-generation key conflict focused tests passed (`+1` each); `./scripts/run_test_gates.sh groups` passed (`+98`); `flutter test --no-pub test/features/groups/integration` passed (`+120`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. |
| `MS-001` | Covered | `send_group_message_use_case.dart` resolves generated and explicit outgoing message ID collisions before pre-persist, allows only matching local failed/sending retry rows to reuse an ID, treats empty requested IDs as generated, and emits collision flow events. `send_group_message_use_case_test.dart` proves generated collision recovery, explicit collision recovery, and legitimate retry reuse; `handle_incoming_group_message_use_case_test.dart` proves conflicting same-ID replay cannot overwrite trusted content; `group_resume_recovery_test.dart` proves pubsub plus inbox replay preserves the live row under conflicting content; `group_messaging_smoke_test.dart` keeps rapid simultaneous sends covered; and `group_multi_device_convergence_test.dart` proves same-user sibling devices can send concurrently without message loss or ID collapse. Live GossipSub hash/sequence collision and receipt behavior remain tracked by LP-013, not MS-001. |
| `MS-002` | Covered | MS-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-002-plan.md`. `go-mknoon/node/pubsub.go` rejects claimed `senderId` versus libp2p transport Peer ID mismatches before member lookup, authorization, signature verification, decrypt, accept, or forwarding, and now includes `transportPeerId` in `group_message:received` events after that validation. Migration 061 adds nullable `group_messages.transport_peer_id`; `GroupMessage`, `group_messages_db_helpers.dart`, and `GroupMessageRepositoryImpl` persist and surface the verified transport identity. `handle_incoming_group_message_use_case.dart`, `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, and `send_group_message_use_case.dart` propagate live, retry, and offline inbox transport Peer IDs and reject nonempty transport/sender mismatches before event-log or message persistence side effects. Commands relied on: focused Go proof passed (`+3`); migration/helper/repository tests passed (`+2`, `+20`, `+29`); fresh full-migration-chain schema check passed (`+1`); focused handle-incoming, drain-inbox, and fake-network MS002 tests passed (`+2`, `+2`, `+1`); full group-message application wildcard passed (`+213`); `./scripts/run_test_gates.sh groups` passed (`+99`); `flutter test --no-pub test/features/groups/integration` passed (`+121`); `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. The shipped device identity unit is the libp2p Peer ID; separate account/device registry and per-device key-package identity are outside MS-002. |
| `MS-003` | Covered | MS-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-003-plan.md`. `handle_incoming_group_message_use_case.dart` clamps incoming timestamps beyond the five-minute future-skew window to receive time before event-log append, membership cutoff checks, persistence, and latest-message selection. `group_conversation_wired.dart` and `group_group_messages_into_threads.dart` now use timestamp/id tie-breakers for live conversation upserts and group feed projection, matching the existing DB and fake-repository ordering contract. Focused tests prove direct handler past/current/near-future/far-future normalization, offline inbox far-future replay/latest selection, fake-network live skew convergence across recipients, wired equal-timestamp order, and feed equal-timestamp order. Commands relied on: focused handle-incoming (`+2`), drain-inbox (`+1`), fake-network live (`+1`), wired (`+1`), feed (`+1`), full group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. MS-004 still owns causal references and concurrent ordering beyond timestamp/id ordering. |
| `MS-004` | Covered | MS-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-004-plan.md`. `group_message_ordering.dart` now provides shared timeline ordering: unrelated messages sort deterministically by timestamp/id, present `quotedMessageId` parents are placed before replies, and cycles fall back to stable timestamp/id order. `GroupMessageRepositoryImpl`, `InMemoryGroupMessageRepository`, `GroupConversationWired`, and `groupGroupMessagesIntoThreads` use that ordering for loaded pages, fake-network/user views, live conversation upserts, and feed projection. Focused tests cover DB and fake repository parent-before-reply when timestamp/id would invert the pair, feed and wired live parent-before-reply, fake-network A/B/C equal-timestamp concurrent sends plus quoted replies converging on every peer, and partition/offline replay preserving parent/reply order plus `quotedMessageId` despite reply ids sorting earlier. Commands relied on: focused repo (`+2`), feed (`+1`), wired (`+1`), fake-network live (`+1`), resume replay (`+1`), full group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. This closes the shipped `quotedMessageId` causal parent reference; vector clocks, previous-state DAGs, account/device registry, and real-device packet proof are not claimed. |
| `MS-018` | Covered | MS-018 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-MS-018-plan.md`. Existing app-layer tests prove `sendGroupMessage` snapshots the latest committed local key into both `GroupMessage.keyGeneration` and encrypted replay `keyEpoch`, keeps epoch 1 when epoch 2 is saved before publish returns, binds before/during/after rotation sends to epochs 1/1/2, keeps pending key-update sends on the old epoch until local commit, persists mixed epoch inbox replay under each envelope epoch, and stores unknown future-epoch replay as one safe undecryptable placeholder without wrong-epoch decrypt or plaintext fallback. `fake_group_pubsub_network.dart` now has a test-only held-delivery hook, and `group_messaging_smoke_test.dart` adds `MS018 rotation race preserves message epochs under out-of-order live delivery`: Alice rotates to epoch 2 while Bob sends before, during, and after Bob's local epoch-2 commit, Charlie receives the live deliveries in reverse order, and Bob, Alice, and Charlie all persist the same message ids under epochs 1/1/2 with no duplicate or rewritten epoch. Commands relied on: new fake-network MS018 proof (`+1`), send MS-018 suite (`+2`), pending key-update send proof (`+1`), epoch inbox replay proof (`+3`), group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+101`), full groups integration (`+123`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. Packet-capture/device-lab proof, account/device registry, MLS commit semantics, and new transport cryptography are not claimed. |
| `OS-001` | Covered | `retry_failed_group_messages_use_case_test.dart` now proves restart-style failed outgoing text, quote, and done-media rows inserted out of order republish in deterministic persisted `timestamp ASC, id ASC` order while preserving original message IDs, timestamps, quote IDs, text, and media attachment state. `retry_failed_group_inbox_stores_use_case_test.dart` proves failed message inbox-store rows drain before reaction replay rows, with each owner ordered deterministically by persisted timestamp/id. Focused deterministic tests, both full retry test files, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. |
| `OS-003` | Open | OS-003 remains prerequisite-blocked by `missing_direct_peer_sync_protocol_primitives`. Evidence on 2026-04-30 found only adjacent relay inbox cursor replay, PubSub validation, topic rejoin, and watchdog recovery paths; no direct group peer sync command, request/response schema for ranges or known heads, hash-chain/state-head owner, signed or hash-verified direct response path, or tampered-response fail-closed direct-sync tests exist in the current repo. Focused drain cursor/tamper/future/replay/dedupe tests, focused group resume recovery partition/replay/resume/dedupe/gap tests, the Go node/bridge group inbox/recovery/PubSub evidence slice, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset, so live direct-peer proof was unavailable. |
| `OS-005` | Covered | OS-005 accepted with explicit follow-up on 2026-04-30. Go node/bridge tests prove group inbox-store request JSON preserves opaque encrypted replay envelopes, uses the versioned inbox protocol, and omits protected plaintext fragments. Flutter send, retry, drain, invite, and resume recovery tests prove pending retry storage, `group:inboxStore`, invite inbox fallback, encrypted replay drain, media descriptors, reactions, dedupe, and recipient-side authorization keep store-and-forward content encrypted or metadata-minimized. Go relay-server tests prove in-memory and Redis group inbox backends preserve opaque replay envelopes across store/retrieve and reject forbidden preview canaries. No production group receipt mailbox payload is shipped; receipt hits are routing-smoke criteria or legacy 1:1 delivery-receipt handling. Live relay/device packet-capture proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-006` | Covered | OS-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-HISTORY-GAP-REPAIR-plan.md`. Production now has durable `GroupHistoryGapRepair` lifecycle storage, relay-authorized cursor gap metadata, relay/Go/Dart `group:historyRepairRange` retrieval, Dart inbox-page history-gap parsing, drain orchestration that records detected/repairing/failed/repaired states, deterministic range-hash validation, authorized multi-source fallback, and repaired encrypted replay envelopes applied through the existing listener/replay path for validation and dedupe. UI coverage keeps active, failed, and repaired gap state separate from backlog-retention expiry. Direct evidence passed: migration/helper gap lifecycle tests (`+4`), bridge helper cursor history-gap parsing (`+4`), focused drain repair tests (`+3`), fake-network resume repair (`+1`), conversation UI repair state (`+1`), fresh full-migration-chain proof (`+1`), Dart bridge history repair (`+1`), retry inbox store regression (`+10`), Go node/bridge history gap and repair-range regex, `go-relay-server go test ./...`, targeted analyzer exit 0 with only info diagnostics, `./scripts/run_test_gates.sh groups` (`+102`), `./scripts/run_test_gates.sh completeness-check` (`708/708`), and `git diff --check`. Host/fake-network proof is primary; live device/relay proof is supporting only. Full MLS history, permanent server archive, packet capture, Android paired-device proof, and broad transport rewrites are not claimed. |
| `OS-008` | Covered | OS-008 accepted on 2026-04-30. `group_resume_recovery_test.dart` proves a removed offline member with a queued failed outgoing row drains the replayed self-removal, leaves/deletes local group state, then `retryFailedGroupMessages` returns zero without issuing any additional `group:publish` or `group:inboxStore` for the stale row; the stale row remains failed. Existing focused send, retry, drain, and resume-recovery tests prove local removed-sender sends are rejected before persistence/bridge calls, failed-message retry reuses that authorization check, replayed self-removal stops later cursor pages, and post-resume send attempts return group-not-found. Go PubSub validator tests prove removed/unauthorized sender traffic is rejected before forwarding. Live device/relay proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-009` | Covered | OS-009 accepted on 2026-04-30. `drain_group_offline_inbox_use_case.dart` now persists a safe incoming `undecryptable` placeholder when an encrypted offline replay envelope carries a message id and key epoch but the local replay key is missing. The placeholder uses generic text only (`Message could not be decrypted.`), records the missing `keyGeneration`, preserves the replay `messageId` for dedupe/replacement, and does not call `group.decrypt` without a key. `drain_group_offline_inbox_use_case_test.dart` proves duplicate future-epoch replay creates one placeholder with no plaintext fallback, while mixed known-epoch replay still decrypts and persists under each envelope epoch. `group_conversation_screen_test.dart` proves the placeholder renders safe text without failed-media controls or guessed plaintext. Go PubSub tests still reject unknown/wrong live epochs before delivery. Live device/relay proof remains supplemental and fixture-blocked because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `OS-010` | Partial | OS-010 closure attempt on 2026-04-30 is fixture/prerequisite-blocked by missing fresh real same-account device-lab evidence. Host fake-network proof remains green: `group_multi_device_convergence_test.dart` covers same-peer sibling sent history, concurrent sends, membership convergence without duplicate local membership, sibling-device versus new-human distinction, device-local unsubscribe, and mute/unread/local notification locality. `group_multi_device_policy_test.dart` now pins composer drafts as device-local state alongside mute, unread counters, local notifications, and pending invite review, while membership, metadata, and message history stay shared across joined devices. The key-update listener slice keeps adjacent member-scoped key convergence/order behavior green. The row remains Partial because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset and no fresh real/equivalent B1/B2 run proves messages, read state, key updates, drafts, and membership together. |
| `OS-012` | Partial | OS-012 closure audit on 2026-04-30 keeps this row Partial. Host/fake-network anchor passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"` returned `00:00 +1: All tests passed!`, proving deterministic fake-network partition replay and post-heal live delivery. Configured real-network gate passed with supplied `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and relay addresses: `./scripts/run_test_gates.sh group-real-network-nightly` returned `00:02 +4: All tests passed!`, but the output reported `No CLI peer fixture` and `No CLI peer — running self-contained scenarios only`; the real CLI peer group recovery path returned early instead of proving real bridge/GossipSub partition-heal backlog plus post-heal live delivery. Exact missing evidence: a configured real bridge/GossipSub or equivalent simulator/device-lab proof where B is actually partitioned from live group delivery while A/C continue, the split-window backlog is stored and replayed to B in order after heal, and post-heal live delivery resumes without duplicate visible rows. Blocker class: `missing_real_bridge_gossipsub_partition_heal_proof`; no production code/tests changed. |
| `NT-001` | Covered | NT-001 accepted on 2026-04-30. `background_push_notification_fallback.dart` now ignores push-visible `title` and `body` for protected data-only `new_message` and `group_message` pushes, keeping generic fallback copy until local decrypt resolves an on-device preview; visible `RemoteMessage.notification` payloads still suppress local fallback, and non-message fallbacks keep their explicit copy path. `background_push_notification_fallback_test.dart` and `background_message_handler_test.dart` prove protected chat and group data-only fallback privacy on Android-style and iOS data-only paths. `push_decrypt_preview_test.dart` proves current push fixtures plus post-phase1 frozen payload route data omit plaintext preview fields (`title`, `body`, `pushTitle`, `pushBody`, `senderUsername`, `groupName`, `messageText`, `text`, and `media`) while decrypted local previews still render 1:1 and group sender/body text after local decrypt. Supporting direct gates passed: `push_preview_telemetry_gate_test.dart`, `handle_foreground_remote_message_use_case_test.dart`, `chat_and_group_push_open_flow_test.dart`, `resolve_group_notification_route_target_use_case_test.dart`, `set_group_muted_use_case_test.dart`, and `group_notification_dedupe_integration_test.dart`. `./scripts/run_test_gates.sh completeness-check` and `git diff --check` passed. |
| `NT-006` | Covered | NT-006 accepted on 2026-04-30. `show_notification_use_case.dart` now checks the recent remote-push announcement gate before showing local notifications even when the app is resumed, while preserving active-conversation suppression and avoiding a foreground delay. `foreground_group_push_drain_test.dart` proves live-plus-foreground-push dedupe and background-announced-plus-foreground-drain dedupe: the same group `messageId` persists one incoming row, unread count stays at one, duplicate local notification is suppressed, unrelated gate entries remain consumable, and a distinct later group message increments unread and notifies normally. `group_notification_dedupe_integration_test.dart` and `group_message_listener_test.dart` prove background push announcements suppress later local PubSub/listener notifications for the same group message. Focused direct push/listener tests, focused drain replay tests, simulator foreground drain, groups integration, canonical `groups` gate, and completeness check passed. The broad ad hoc `flutter test --no-pub test/features/groups` folder sweep still fails one unrelated MD-011 media/epoch replay assertion in `drain_group_offline_inbox_use_case_test.dart`; the canonical `./scripts/run_test_gates.sh groups` command is green. |
| `DB-001` | Covered | DB-001 closed on 2026-04-30. `test/core/database/migrations/017_018_group_original_tables_test.dart` proves migrations 017/018 create the original group tables (`groups`, `group_members`, `group_keys`, and `group_messages`), expose expected baseline columns/defaults/indexes, support baseline group/member/key/message insert and query before migration 026, enforce original type, role, unique-topic, member primary-key, and key primary-key constraints, and rerun idempotently. Direct gate `flutter test --no-pub test/core/database/migrations/017_018_group_original_tables_test.dart` passed with 3 tests. No production migration code changed. |
| `DB-002` | Covered | DB-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-DB-002-plan.md`. `lib/core/database/migrations/060_group_event_log.dart` and `lib/core/database/helpers/group_event_log_db_helpers.dart` provide the tamper-evident per-group hash-chain event log with canonical payloads, source-event uniqueness, idempotent exact replay, conflicting replay rejection, and row tamper verification. `lib/main.dart` wires `dbAppendGroupEventLogEntry` into the group message, invite, and direct key-update listeners; the DB-002 session added the missing production key-update listener wiring. Application anchors prove accepted incoming messages, membership/metadata/role system events, `key_rotated` system events, and direct key commits append or replay safely without silent local DB mutation. Focused commands passed: event-log migration/helper suite (`+5`), handle-incoming event-log slice (`+3`), new DB-002 membership/metadata listener proof (`+1`), role replay proof (`+1`), `key_rotated` duplicate proof (`+1`), direct key-update tamper proof (`+1`), exact duplicate direct key-update replay proof (`+1`), and fresh full migration-chain schema check (`+1`). DB-002 does not claim MLS signed commit-transition support, first-class key-package replay protection, external device proof, or a per-actor signed audit model. |
| `DB-004` | Covered | DB-004 covered on 2026-05-01 by `PREREQ-GROUP-SYNC-RECEIPTS` final QA. Migration 066 creates durable `group_inbox_cursors` and `group_message_receipts`, `group_sync_receipts_db_helpers.dart` persists cursors/receipts and applies message insert, receipt/read-state update, and cursor advancement inside one SQLite transaction, and `GroupMessageRepositoryImpl` plus `main.dart` expose transaction-scoped page apply to production. `drain_group_offline_inbox_use_case.dart` now loads the durable cursor before replay and advances it only through `runInboxPageTransaction`. `group_message_listener.dart` supports transaction-scoped normal and system replay with `msgRepoOverride` and `rethrowOnError: true`; system timeline saves use the supplied repository so listener failures roll back timeline rows/events together with receipts/read-state and cursor advancement. Direct evidence passed: migration 066 test (`+1`), sync helper tests (`+4`), repository PREREQ tests (`+2`), drain PREREQ tests (`+5`), v65-to-v66 and fresh-install full-chain migration proofs, full listener regression suite (`+88`), `./scripts/run_test_gates.sh groups` (`+102`), `./scripts/run_test_gates.sh completeness-check` (`710/710`), scoped analyzer with documented pre-existing listener warning debt outside the clean slice, and `git diff --check`. |
| `DB-006` | Covered | DB-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-SECRET-STORAGE-WRAPPING-plan.md`. `lib/core/secure_storage/secret_storage_references.dart` defines deterministic `secure:` references for group media attachment keys and group key material, and `legacy_group_secret_storage_scrub.dart` migrates legacy plaintext-equivalent `media_attachments.encryption_key_base64` and `group_keys.encrypted_key` rows into `SecureKeyStore` while rewriting SQL to non-secret references. `MediaAttachmentRepositoryImpl` and `GroupRepositoryImpl` now store actual key material in the primary secure store, persist only references in ordinary SQL rows, hydrate models when secure material exists, fail closed when referenced material is missing, and avoid mirroring unresolved `secure:` reference text into shared push storage. `main.dart` runs the legacy scrub before group-key mirroring and injects the primary secure store into production media/group repositories. Evidence passed: PREREQ media repository tests (`+5`), PREREQ group repository tests (`+5`), PREREQ legacy scrub tests (`+3`), media/group helper tests, fresh full-migration-chain proof, targeted analyzer, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`711/711`), and `git diff --check`. This closes local ordinary-table secret persistence only; DB-012 and EK-012 remain separate event-family/replay rows. |
| `DB-012` | Covered | DB-012 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md`. The last row-named event-family gaps now have production apply models/tests: trusted-private `member_banned`, `member_unbanned`, and `group_message_deleted` route through `GroupMessageListener` with deterministic tombstone/timeline rows, duplicate replay idempotency, stale-state guards, authorization, signed transition audit/event-log wiring, and offline replay through the existing transaction-scoped listener path. Existing evidence covers duplicate/idempotent apply for messages, media enrichment, reactions, `member_added`, `members_added`, non-self/self `member_removed`, `member_role_updated`, signed `group_metadata_updated`, `group_dissolved`, `key_rotated`, direct `group_key_update`, welcome/key-package tombstones, durable receipts, and live-plus-inbox duplicate replay. Evidence passed: `group_message_listener_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+3`), `drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+1`), Go invalid-signature regex, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`; targeted analyzer has only documented pre-existing listener warnings. |
| `ER-001` | Covered | ER-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-001-plan.md`. `go-mknoon/node/pubsub.go` now emits rate-limited `group:validation_rejected` diagnostics from validator reject paths using only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`; validator logs use the same hashed identifiers. `go-mknoon/node/pubsub_authorization_forward_test.go` adds `TestER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable`, which injects invalid signatures for shipped event families including messages, reactions, `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`, then proves rejection, one actionable diagnostic, and no raw group IDs, peer IDs, group names, keys, signatures, ciphertexts, nonces, plaintext, or sensitive multiaddrs in logs or diagnostic events. `lib/core/bridge/go_bridge_client.dart` now forwards `group:validation_rejected` into Flutter's `groupDiagnosticEventStream`, and `go_bridge_client_test.dart` proves this does not invoke the normal group-message callback. Focused commands passed: Go ER-001/LP-002/security-family slice and the Flutter bridge validation-reject slice. Unmodeled bans, remote deletes, receipts, and commit/key-package transitions remain outside ER-001 until those event families are first-class. |
| `ER-002` | Covered | ER-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-002-plan.md`. `handle_incoming_group_message_use_case.dart` now rejects unknown senders with no persisted removal cutoff before event-log append or message persistence, while preserving intentional pre-removal cutoff tolerance and rejecting at-cutoff/later removed-sender replay. `handle_incoming_group_reaction_use_case.dart` now returns `unknownSender` before reaction storage when the sender is not a current member. `group_message_listener_test.dart` adds ER-002 proof that an unknown-sender group message creates no DB row, emits no group-message stream item, and shows no local notification. Existing fake-network membership smoke still proves removed members receive no notifications while removed and only resume after rejoin. Focused commands passed: handle-incoming unknown sender slice (`+3`), reaction unknown sender slice (`+1`), listener ER-002 slice (`+1`), and removed-member notification smoke (`+1`). First-class receipt traffic is not modeled and remains outside ER-002 until it exists. |
| `ER-004` | Covered | ER-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-FUTURE-EPOCH-KEY-REPAIR-plan.md`. Go live wrong-key, tampered nonce, tampered ciphertext, unknown future epoch, and expired previous-epoch diagnostics remain green without normal `group_message:received`; Flutter bridge still forwards `group:decryption_failed` only to diagnostics. `GroupMessageListener` now turns live decryption-failure diagnostics into a safe pending repair placeholder, queues a durable pending item, and triggers scoped key repair without plaintext delivery. Offline missing/future-key replay shares the same pending/finalized status model, retries after key arrival, replaces placeholders on valid repair, and finalizes invalid or no-envelope repairs idempotently as safe `undecryptable` text. Commands relied on: focused Go diagnostics regex passed; Flutter bridge diagnostic preservation passed (`+1`); focused live placeholder test passed (`+1`); focused offline queue/repair test passed (`+1`); focused key-arrival and rejected-key tests passed (`+2`); focused pending/finalized UI test passed (`+1`); migration/helper/repository/full-chain tests passed (`+12`); direct owner suites, `groups`, `completeness-check`, and `git diff --check` passed. |
| `ER-005` | Covered | ER-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-ER-005-plan.md`. `flow_event_emitter.dart` now sanitizes flow-event payloads before test sinks and debug logs, recursively redacting sensitive keys such as private keys, secret keys, public keys, ciphertext, plaintext, signatures, nonces, key material, relay/listen/circuit multiaddrs, and long Peer IDs. `bridge.dart` applies the same sanitizer to group diagnostic stream payloads before Flutter listeners receive them. `go_bridge_client.dart` sanitizes native `ok:false` bridge error messages and `PlatformException` or unexpected exception text before returning JSON responses or emitting flow events. Focused evidence passed: `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart` (`+7`), `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'ER005'` (`+3`), `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'PlatformException'` (`+3`), full `go_bridge_client_test.dart` (`+68`), and `git diff --check`. ER-005 closes the shared bridge/diagnostics emission boundary without changing native command payloads. |
| `AB-006` | Covered | AB-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-AB-006-plan.md`. Existing media policy, send, listener, offline replay, and fake-network tests prove suspicious media does not auto-download or reach side effects before validation. Policy tests cover dangerous/unsupported MIME, mediaType mismatch, oversized single and aggregate media, malformed remote sizes, content-hash display prerequisites, and tampered hash checks. Send tests prove dangerous MIME, oversized attachments, and mediaType mismatch reject before message/media persistence, group publish, or group inbox storage. Listener tests prove invalid, oversized, and hashless media reject before notification preview or `media:download`. Offline replay rejects dangerous encrypted media before message or attachment storage. Fake-network tests prove oversized recipient media is neither stored nor downloaded, and tampered downloads become integrity failures with deleted local files before done/display state. Focused AB-006 commands passed: core media policy suite (`+18`), send dangerous MIME (`+1`), send oversized (`+2`), send mediaType mismatch (`+1`), listener auto-download guards (`+3`), dangerous offline replay (`+1`), oversized fake-network fanout (`+1`), tampered fake-network integrity (`+1`), and `git diff --check`. |
| `UI-003` | Covered | UI-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-UI-003-plan.md`. `group_security_status_view_state.dart` derives a display-only security state from latest group key epoch, verified saved-contact matches, identity-change warnings, unverified member counts, and member totals without exposing group key material. `group_info_screen.dart` now renders a scrollable security card with encrypted-state, current/key-changed epoch text, verified-member counts, and verification warnings while preserving existing first-screen member/admin controls. `group_conversation_screen.dart` now renders a compact encrypted/key-epoch and review warning strip. `group_info_wired.dart` and `group_conversation_wired.dart` populate those surfaces from `GroupRepository.getLatestKey`, group members, contacts, and existing `GroupMemberIdentitySafety.compare`. Direct evidence passed: focused UI-003 pure/wired tests, full `group_info_screen_test.dart` (`+18`), full `group_conversation_screen_test.dart` (`+35`), full `group_info_wired_test.dart` (`+28`), full `group_conversation_wired_test.dart` (`+74`), and `git diff --check`. Existing member-row safety-number warnings remain covered by the earlier group info tests. |
| `UI-005` | Covered | UI-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-UI-005-plan.md`. `drain_group_offline_inbox_use_case.dart` uses `groupUndecryptablePlaceholderText` and saves one `status: 'undecryptable'` placeholder when future-epoch encrypted replay arrives without matching local key material, preserving key-generation metadata while avoiding `group.decrypt` and original plaintext exposure. `group_conversation_screen_test.dart` proves the conversation UI renders the generic safe text, hides the original future-epoch plaintext, and does not expose failed-media retry/delete controls on undecryptable rows. Focused evidence passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` (`+1`), `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders undecryptable epoch placeholders as safe text'` (`+1`), and `git diff --check`. The missing live repair lifecycle remains ER-004 scope. |
| `SP-001` | Covered | SP-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-001-plan.md`. `go-relay-server/inbox.go` now requires authenticated group inbox store callers to bind `from` to the libp2p `RemotePeer`, rejects empty `recipientPeerIds`, persists normalized per-message recipient ACLs through `backend_memory.go` and `backend_redis.go`, and filters `group_retrieve` / `group_retrieve_cursor` to the sender or stored recipients only. `go-relay-server/inbox_test.go` adds `TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer`, `TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization`, and `TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages`. Existing Go proof covers the other shipped protocol surfaces: `go-mknoon/node/protocol_version_test.go` requires secure libp2p negotiation before mknoon protocols; `pubsub_test.go` and `pubsub_authorization_forward_test.go` prove PubSub sender/member/signature/system-event authorization; `go-relay-server/media_test.go` keeps unauthorized media download/delete/list ACLs pinned. Focused evidence passed: `cd go-relay-server && go test ./... -run 'GroupInbox|HandleInboxStream|Unauthorized|RedisGroupInbox|TwoRelayServers_SharedGroupInbox' -count=1`, `cd go-mknoon && go test ./node -run 'TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers|Protocol|PubSub|Group|Security' -v -count=1`, and `git diff --check`. Relay group inbox authorization enforces authenticated transport peer plus stored fanout ACL; live authoritative group-state control-plane semantics remain separate scope. |
| `SP-002` | Covered | SP-002 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-002-plan.md`. Existing node proof keeps group topics, rendezvous namespaces, join logs, and relay-visible PubSub envelopes free of human-readable group metadata and plaintext. This session removed the remaining native group inbox preview leak: `go-mknoon/node/group_inbox.go` no longer serializes retired `pushTitle` / `pushBody`, `group_inbox_test.go` proves caller-supplied preview fields are omitted, and `go-mknoon/bridge/bridge.go` ignores those legacy JSON fields on `group:inboxStore`. `retry_failed_group_inbox_stores_use_case_test.dart` proves stale persisted retry payloads containing old preview fields replay through the Flutter bridge without re-emitting them. Existing relay, push, and diagnostics tests prove encrypted group pushes are generic/data-only and diagnostic surfaces redact raw secrets, raw Peer IDs, and sensitive multiaddrs. Focused evidence passed: Go node metadata/request/protocol slice, Go bridge `GroupInboxStore` slice, relay `GroupPush|Push|Forbidden|GroupInbox|Unauthorized` slice, Flutter retry inbox-store suite (`+10`), push fallback/preview suite (`+34`), diagnostics regex slice (`+8`), and `git diff --check`. Relay-visible group IDs, recipient peer IDs, push tokens, relay addresses, and encrypted replay blobs remain unavoidable relay metadata and are not claimed hidden. |
| `SP-003` | Covered | SP-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-SP-003-plan.md`. Added focused random-artifact proof across shipped surfaces: `go-mknoon/crypto/group_test.go` checks repeated group AES keys and AES-GCM nonces/ciphertexts for expected byte lengths and uniqueness; `go-mknoon/crypto/x25519_test.go` checks X25519 ephemeral public keys used as HKDF salts plus nonces/ciphertexts for uniqueness; `go-mknoon/identity/identity_test.go` checks repeated BIP39 identity mnemonics and Peer IDs; `go-mknoon/bridge/bridge_test.go` checks UUID v4 group IDs, UUID v4 native publish message IDs, and 32-byte group keys; Flutter send/invite use-case tests check unique UUID v4 message IDs and direct invite IDs. Gates passed: Go crypto/identity/bridge SP003 slice, Flutter SP003 group send/invite slice (`+2`), Go node `Protocol|PubSub|Group|Security`, Flutter push preview plus group-key DB helper suite (`+15`), Dart format, and `git diff --check`. No separate public/link invite-token generator is shipped; direct invites use UUID v4 invite IDs, push tokens are externally supplied, and contact safety numbers are deterministic rather than random salts. |
| `EC-001` | Covered | EC-001 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-001-plan.md`. `accept_pending_group_invite_use_case.dart` now returns `wrongIdentity` for copied pending invites whose signed `recipientPeerId` / `allowedDevices` do not match the current local Peer ID, keeping that case distinct from malformed/tampered `invalidPayload`; group list and Orbit pending-invite surfaces show a distinct wrong-identity snackbar. `accept_pending_group_invite_use_case_test.dart` adds `EC001 invalid invite accepts classify failures without group or key state`, proving expired, revoked, wrong-identity, malformed signed-payload, and already-used accepts produce the expected classifications and create no group, key, join, or message side effects. Supporting store-path evidence proves delayed revoked, already-used, expired, and local-identity-mismatched invite copies do not create pending or group state. Gates passed: focused EC001/IJ013 accept slice (`+2` after stale assertion recovery), full accept-pending suite (`+20`), supporting store-pending edge slice (`+4`), Dart no-change format, scoped analyzer with one non-blocking existing style info, and `git diff --check`. |
| `EC-003` | Covered | EC-003 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-003-plan.md` for shipped future-input behavior. `handle_incoming_group_message_use_case_test.dart` proves far-future incoming timestamps clamp to receive time and past/current/near-future timestamps retain chronological order. `group_messaging_smoke_test.dart` proves fake-network live skewed timestamps keep sane ordering/latest-message state after valid membership hydration; this session fixed the smoke fixture to broadcast Charlie's membership before Charlie publishes under strict sender validation. `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves unknown live future epochs reject before delivery. `drain_group_offline_inbox_use_case_test.dart` proves offline future-epoch encrypted replay stores one generic undecryptable placeholder without decrypting/exposing future plaintext and that later valid replay can enrich sparse prior rows with quote/media dependencies. Focused Go, Flutter application, offline replay, fake-network smoke, duplicate-enrichment, Dart no-change format, and `git diff --check` evidence passed. Durable future-key queue/key-sync repair and live repair lifecycle remain EK-005/ER-004 scope. |
| `EC-004` | Covered | EC-004 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-004-plan.md` with evidence-only closure. `group_message_listener_test.dart` proves older metadata, member-added, member-removed, and member-role events cannot roll back newer finalized state across restart, and old system events after dissolve or local delete do not mutate metadata, members, keys, or visible messages. `handle_incoming_group_message_use_case_test.dart` and `handle_incoming_group_reaction_use_case_test.dart` prove pre-dissolve messages/reactions are accepted while at/after-cutoff replay is ignored without overwriting trusted rows. Fake-network membership and resume-recovery tests prove removed-sender replay is accepted only before the removal cutoff, conflicting promote/remove converges to removal, remove-vs-send backlog drain keeps the same cutoff outcome after resume, and offline metadata replay converges to the newer final state. Focused commands passed: listener old-event slice (`+6`), message dissolve-cutoff slice (`+3`), reaction dissolve-cutoff slice (`+3`), membership cutoff smoke (`+1`), promote/remove conflict smoke (`+1`), resume remove-vs-send backlog (`+1`), resume metadata convergence (`+1`), and `git diff --check`. No production code changed for this row. |
| `EC-006` | Covered | EC-006 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md`. `trusted_private_group_system_event.dart` and `GroupMessageListener` now model the missing tombstone families: `member_banned`, `member_unbanned`, and `group_message_deleted`. Duplicate replay creates one deterministic tombstone/timeline row; stale ban replay after a later unban/rejoin does not remove current valid membership; unban is a tombstone/freshness event and does not recreate membership; remote delete removes only the exact same-group target message and ignores wrong-group, missing, stale, newer-message, or unauthorized deletes. Offline replay uses the same listener path through `drainGroupOfflineInbox`, preserving transaction/cursor behavior. Prior evidence still covers removal, voluntary leave, dissolve, local-delete, and re-invite tombstone paths. Evidence passed: PREREQ listener tests (`+3`), offline replay test (`+1`), Go invalid-signature regex, `groups`, `completeness-check`, and `git diff --check`; targeted analyzer caveat remains warning-only pre-existing listener debt. |
| `EC-007` | Covered | EC-007 covered on 2026-05-02 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-INVITER-FRESHNESS-plan.md`. `group_invite_payload.dart` adds signed `GroupInviteMembershipFreshnessProof` and binds it into canonical invite signing; `group_invite_auth.dart` validates proof structure, trusted inviter key, current inviter membership/permission snapshot, group config hash, recipient/device/key-package binding, issue time, and expiry. `send_group_invite_use_case.dart` reloads current `GroupRepository` membership/config state before proof/sign/encrypt/delivery, so stale caller configs from removed/demoted inviters fail before delivery. `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, and `accept_pending_group_invite_use_case.dart` reject missing, malformed, tampered, mismatched, or stale proofs before pending/group/key/join/mailbox/notification/consumption side effects; accept-time stale proof deletes pending state without consumed or welcome-package tombstones. The fix pass made `GroupInviteListener` validate pending-store freshness against local receive time rather than replayed `ChatMessage.timestamp`, and tests keep the original queued timestamp while advancing local receipt beyond `groupInviteMembershipFreshnessTtl`. Evidence passed: PREREQ selectors for invite payload, send invite, create fanout, contact picker fanout, direct handle, listener, accept, and invite round trip; invite wildcard; full invite round trip; valid fresh and remove-rotate-reinvite preservation selectors; targeted analyzer; `groups`; `completeness-check`; and `git diff --check`. Existing queued role update, queued invite/add recheck, receive-side stale mutation rejection, and invalid signed-snapshot rejection evidence remains part of the row closure. |
| `GEK-001` | Covered | GEK-001 covered on 2026-05-09 by `94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md` and the session breakdown closure audit. `group_key_update_listener.dart` now serializes direct key-update handling, preserves non-conflicting stale older material only as non-promoting historical material, and rejects/ignores same-generation conflicting material before event-log append, `group:updateKey`, local replacement, or pending-repair retry; duplicate same-generation material is idempotent. `group_key_update_listener_test.dart` proves delayed older key updates do not promote active state, same-generation conflicts keep first accepted material, duplicates are idempotent, and conflicting historical material is not replaced. `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves `UpdateGroupKey` ignores same-epoch different material and older epochs while preserving the current key, previous-key grace state, and grace deadline. Evidence passed: focused GEK-001 red/green listener tests, focused Go monotonic command, full listener file, `./scripts/run_test_gates.sh groups`, and `git diff --check`; the conditional persistence sweep was skipped because no persistence files changed. GEK-002, GEK-003, GEK-004, and GEK-005 are recorded separately; GEK-005 final verdict is `residual_only` due only exact live three-party GEK proof scope outside this row. |
| `GEK-002` | Covered | GEK-002 covered by `94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`, the session breakdown closure audit, and the GEK-005 recovery pass. `group_pending_key_repair_service.dart` now supersedes a matching pending no-envelope live diagnostic repair when durable replay supplies the canonical real `messageId`, deletes the synthetic live placeholder row, finalizes the live repair, and leaves the durable replay row as the one pending/repaired visible message. `drain_group_offline_inbox_use_case_test.dart` proves the combined live `group:decryption_failed` diagnostic plus duplicate durable replay plus later key arrival journey repairs exactly one visible plaintext row and does not create a fake delivered live row, orphan placeholder, duplicate replay row, or duplicate retry result. Evidence passed: focused GEK-002 red/green regression, required focused prerequisite selectors 2 through 6, full `group_message_listener_test.dart`, `./scripts/run_test_gates.sh groups`, and `git diff --check`. The original explicit follow-up for older `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixtures is now closed: `drainGroupOfflineInbox` accepts an optional retention clock, the affected fixtures pin it, and full `drain_group_offline_inbox_use_case_test.dart` plus broad `test/features/groups` pass. GEK-003 and GEK-004 are recorded separately as closed; GEK-005 final verdict is `residual_only` due only exact live three-party GEK proof scope outside this row. |
| `GEK-003` | Covered | GEK-003 closed on 2026-05-09 by `94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md` and the session breakdown closure audit. `group_pending_key_repair_service.dart` now derives durable replay repair identity from the signed replay envelope account sender and transport identity before falling back to relay `from`, so replay repairs created from a device-level relay sender still match the live diagnostic account sender. `drain_group_offline_inbox_use_case_test.dart` proves the combined Alice/Bob/Charlie partial key-update race: Alice rotates to epoch 2, Bob commits epoch 2 while Charlie remains on epoch 1, Bob sends immediately on epoch 2, Alice/current-key replay succeeds, Charlie records a pending-key live diagnostic state, durable replay becomes canonical under Bob's real message id, Charlie's later key arrival repairs exactly one delivered plaintext row, and duplicate replay/retry stays exactly once. Evidence passed: focused GEK-003 regression, required key-update/send/GEK-002 safety selectors, `./scripts/run_test_gates.sh groups` (`103` tests), QA review, and `git diff --check`. GEK-004 is recorded separately as closed; GEK-005 final verdict is `residual_only`, and the GEK-002 `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixture follow-up is closed. |
| `GEK-004` | Covered | GEK-004 closed on 2026-05-09 by `94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md` and the session breakdown closure audit. `drain_group_offline_inbox_use_case.dart` now defers signed durable group-message replays rejected as `unknown_sender` within a drain page and retries them before cursor commit after membership/config/system replay, so a newly accepted sender's durable message can recover once delayed `member_added` config makes that sender locally known. `drain_group_offline_inbox_use_case_test.dart` proves `GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once`: the pre-catch-up replay creates no ghost row and does not advance the cursor, the catch-up page applies the new member/device config, the same durable message is delivered under the correct sender/device/message identity, and duplicate replay remains exactly once. Evidence passed: focused GEK-004 red/green regression, required GEK-001/GEK-002/GEK-003 safety selectors, membership/config and invite-truth selectors, QA reruns of the GEK-002 and GEK-003 drain selectors, `./scripts/run_test_gates.sh groups`, and `git diff --check`; `completeness-check` was skipped because no `_test.dart` file was added, removed, or renamed. This is host deterministic app-layer closure only: unresolved unknown senders still reject before cursor advancement, live unknown senders remain fail-closed, invite eligibility semantics, per-recipient ACKs, Go/native behavior, and exact live three-party GEK split-delivery proof did not change. GEK-005 final verdict is `residual_only`, and the GEK-002 fixed-date receipt-fixture follow-up is closed. |
| `GEK-005` | Accepted | GEK-005 final reconciliation and recovery ran on 2026-05-10 by `94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md` and the session breakdown final verdict. All 17 GEK-focused Dart selectors passed; full `group_key_update_listener_test.dart`, `group_message_listener_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, and broad `flutter test --no-pub test/features/groups` passed; focused and broad Go passed; `./scripts/run_test_gates.sh groups` passed; `./scripts/run_test_gates.sh completeness-check` passed with `730/730` test files classified; `git diff --check` passed; generated tracked artifacts from the Go/relay runs were restored; the configured single-device real-network nightly passed as self-contained smoke without CLI peer fixture; and the paired iOS relay script passed its MD-004 primary/sibling proof. Final program verdict is `residual_only` because the remaining limitation is an exact live three-party GEK stale-key/decrypt-repair split-delivery proof, not a repo-owned host/Go/gate blocker. `test-gate-definitions.md` was inspected through completeness-check and not changed by GEK-005. |
| `MD-001` | Covered | `group_media_mime_policy_test.dart` proves the exact group media MIME allowlist, declared-MIME rejection, mediaType mismatch rejection, dangerous signature rejection, and known signature mismatch rejection. Upload, send, retry, live receive, encrypted replay, listener, download, and display tests prove invalid declared MIME and spoofed bytes fail before bridge upload, publish/inbox payload creation, local message/media storage, notification preview, auto-download, done-state marking, or thumbnail render. `group_media_fanout_test.dart` preserves existing allowed image/video/voice fan-out. `SMOKE-GAP-05` is satisfied by the focused direct suites plus the group media fanout, broad groups, groups integration, `groups` gate, and `completeness-check` gate; it is not a shell command. No Go/relay MD-001 tests were required because MD-001 changed only Flutter group boundaries. |
| `MD-002` | Covered | `group_media_size_policy_test.dart` proves exact boundary acceptance, per-media overage, total-message overage, malformed/missing/zero/negative/non-integer remote sizes, oversized integer rejection, GIF cap preservation, and MIME-policy separation. Upload, wired composer, voice, send, retry, live receive, encrypted replay, listener, foreground push drain, download, display, and fake-network fan-out tests prove oversized group media is rejected before bridge upload, durable pending-row storage, publish/inbox payload creation, retry resend, local message/media storage, notification preview, auto-download, `media:download`, done-state marking, or thumbnail render. The unqualified foreground integration command was not runnable as written because Flutter detected multiple devices and required `-d`; the same test passed with `-d macos`. `SMOKE-GAP-05` is satisfied by the focused direct suites plus group media fanout, broad groups, groups integration, `groups` gate, and `completeness-check` gate; it is not a shell command. No Go/relay MD-002 tests were required because MD-002 changed only Flutter group boundaries. |
| `MD-003` | Covered | `group_media_integrity_policy_test.dart` anchors SHA-256 normalization, malformed digest rejection, file hash verification, and display eligibility. Model, migration, DB helper, upload, download, send, retry, live receive, encrypted replay, listener, foreground push, feed, group conversation, media-grid, audio, fake-network fan-out, and hydration tests prove group media content hashes are first-class, sent in live/replay descriptors, required before storage, verified before `downloadStatus: done`, and required before display. Tampered downloads are deleted and marked `integrity_failed`; legacy hashless `done` group media renders unavailable instead of media bytes. Thumbnail closure is by absence of any production remote thumbnail display path plus generated thumbnails deriving only from verified content; optional `thumbnailHash` metadata still validates when present. `SMOKE-GAP-05` is satisfied by the focused direct suite, group media fanout, macOS foreground push drain, broad groups, groups integration, `groups` gate, `completeness-check`, and `git diff --check`; it is not a shell command. One plan-listed `feed_wired_test.dart` focus target remains blocked by an unrelated dirty-tree `orbit_wired.dart` switch exhaustiveness error for `AcceptPendingGroupInviteResult.repairPending`; narrower feed application/widget MD-003 tests passed. No Go/relay MD-003 tests were required because MD-003 did not change Go protocol structs or media responses. |
| `MD-004` | Covered | Proof-first upload regression failed on the previous contract because group media had no per-object encryption key/nonce metadata and uploaded the selected file path directly. `MediaAttachment`, DB migration 059, helper/model tests, upload/download use-case tests, send/receive/retry/listener tests, wired tests, fake-network media fanout, new-member onboarding, announcement onboarding, resume recovery, and foreground push drain now prove each group media object is encrypted before relay upload with fresh object key/nonce metadata, encrypted blob hashes are verified before decrypt, plaintext MIME/size is validated after decrypt, live publish plus encrypted replay preserve protected metadata, and cross-object wrong-key decrypt attempts fail without display. Focused suites passed, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed, `flutter test --no-pub test/features/groups` passed with `+993`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `693/693` classified, and `git diff --check` passed. `SMOKE-GAP-05` is this evidence bundle, not a shell command. No Go/relay MD-004 tests were required because no Go or relay protocol code changed. |
| `CB-004` | Accepted | `create_group_with_members_use_case_test.dart` now pins mixed invite degradation; `create_group_picker_wired_test.dart` proves the create flow surfaces an explicit warning instead of implying full invite success. |
| `CB-005` | Accepted | `create_group_with_members_use_case_test.dart` now proves config-sync rollback and publish-warning truth; `contact_picker_wired_test.dart` keeps the add-member picker truthful under the same degraded branches. |
| `CB-006` | Accepted | `group_name_panel_test.dart` now proves the shipped create surface exposes only the name field, `create_group_picker_wired_test.dart` proves the create payload omits `description`, and `group_info_wired_test.dart` keeps later edit-time description handling explicit. |
| `CB-007` | Accepted | `create_group_use_case.dart` now falls back to `/mknoon/group/$groupId`, `create_group_use_case_test.dart` pins creator-path persistence on that namespace, and `rejoin_group_topics_use_case_test.dart` already proves rejoin callers consume the stored `topicName`. |
| `CB-008` | Accepted | `create_group_use_case_test.dart` now proves keyless create rolls back the local group and throws instead of returning success into an unusable state. |
| `DV-003` | Accepted | `group_message_listener_test.dart`, `contact_picker_wired_test.dart`, and `group_membership_smoke_test.dart` now pin durable `members_added` history across listener, picker, and recipient surfaces. |
| `DV-004` | Accepted | `accept_pending_group_invite_use_case_test.dart`, `group_list_wired_test.dart`, `group_message_listener_test.dart`, and `invite_round_trip_test.dart` now prove durable `member_joined` history across accept, shipped accept-surface, listener, and existing-member render flows, including the degraded `bridgeError` branch. |
| `DV-008` | Accepted | `group_info_wired_test.dart` and `group_membership_smoke_test.dart` now prove voluntary leave broadcasts a truthful self-removal event and remaining members persist `left the group` history. |
| `DV-013` | Accepted | `send_group_invite_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, and `contact_picker_wired_test.dart` now pin per-recipient batch invite outcomes and user-visible warning surfaces. |
| `DV-014` | Accepted | `create_group_with_members_use_case_test.dart`, `contact_picker_wired_test.dart`, and `create_group_picker_wired_test.dart` now pin the explicit no-latest-key warning contract for create and add-member flows. |
| `ID-001` | Accepted | `create_group_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, and `group_info_wired_test.dart` now prove the creator username is persisted, exported in `groupConfig`, and rendered for other members instead of falling back to a raw peer ID. |
| `ID-002` | Accepted | `group_member_row.dart` now reuses `UserAvatar`, and `group_info_screen_test.dart` plus `group_conversation_screen_test.dart` now prove member-list and conversation surfaces render participant identity with the same avatar component family. |
| `ID-004` | Unsupported | `create_group_picker_wired.dart` and `contact_picker_wired.dart` restrict onboarding selection to active contacts, while `handle_incoming_group_invite_use_case_test.dart` proves invites from non-contacts are rejected as `unknownSender`; the repo does not ship a non-friend onboarding path. |
| `ID-010` | Accepted | `group_info_screen_test.dart` and `group_conversation_screen_test.dart` now prove both group surfaces keep readable participant names and fall back to `RingAvatar` when no profile photo exists. |
| `CX-001` | Accepted | `group_conversation_screen.dart` now routes group long-press through `MessageContextOverlay`, and `group_conversation_screen_test.dart` proves the selected preview, reply/copy actions, and coherent overlay surface. |
| `CX-002` | Accepted | `group_conversation_screen_test.dart` now proves the long-press reply action enters the existing group quote-reply callback with the correct message id. |
| `CX-003` | Accepted | `group_conversation_screen_test.dart` now proves long-press copy writes exact multiline/emoji text to the clipboard, dismisses the overlay, and shows the copied snackbar. |
| `CX-004` | Accepted | `group_conversation_screen_test.dart` now proves the group context surface stays available for supported actions while unsupported edit/delete actions remain hidden. |
| `CX-005` | Accepted | `group_conversation_screen_test.dart` plus `group_conversation_wired_test.dart` now prove reply/copy stay available even when reaction handling is unavailable. |
| `CX-006` | Accepted | `group_conversation_screen_test.dart` now proves the overlay keeps reaction selection alive while the existing swipe-to-quote and row-render coverage remains intact. |
| `CX-007` | Accepted | `orbit_wired_test.dart`, `feed_wired_test.dart`, and `group_conversation_wired_test.dart` now pin the same long-press action contract from Orbit, Feed, and notification-anchor entry points. |
| `UI-001` | Accepted | `group_conversation_screen_test.dart` now proves the group row host keeps exactly one row-local shell across base text, quoted/reaction, and media variants. |
| `UI-002` | Accepted | `group_conversation_screen_test.dart` now re-renders the same row through media and reaction enrichment and proves the shell stays single after the update. |
| `RX-001` | Accepted | `group_reaction_details_sheet.dart` plus `group_conversation_wired_test.dart`, `feed_wired_test.dart`, and `orbit_wired_test.dart` now prove visible group chips open a participant-inspection surface instead of silently mutating. |
| `RX-002` | Accepted | `group_conversation_screen.dart` and `feed_screen.dart` now separate chip inspection from long-press mutation, and `group_conversation_wired_test.dart` proves chip taps leave stored reactions untouched. |
| `RX-003` | Accepted | `group_reaction_details_sheet.dart` now resolves `You`, member usernames, and readable peer-id fallback from group membership state, and `group_conversation_wired_test.dart` proves that lookup directly. |
| `RX-004` | Accepted | `orbit_wired_test.dart` and `feed_wired_test.dart` now pin the same reaction-inspection sheet contract after entering the group from Orbit or Feed. |
| `RX-005` | Accepted | `feed_screen_test.dart` now proves inline group chips route through inspection on both discussion and announcement-reader cards, while `feed_wired_test.dart` keeps Feed-to-conversation inspection parity. |
| `RX-006` | Accepted | `group_reaction_roundtrip_test.dart` proves live reaction fan-out, `announcement_happy_path_test.dart` now proves the announcement-reader path also lands a durable stored replay row, and `group_resume_recovery_test.dart` proves resume/rejoin replay keeps one truthful stored reactor after live-plus-replay dedupe and after post-rotation recovery on a rotated message. |
| `MM-009` | Accepted | `send_group_message_use_case_test.dart` pins the zero-peer plus inbox-fail branch, `retry_failed_group_messages_use_case_test.dart` proves the failed row recovers through the failed-message retry owner, and `group_resume_recovery_test.dart` now proves inbox-store retry skips that failed row while failed-message retry recovers it in place and restores offline delivery. |
| `MM-012` | Accepted | `send_group_message_use_case_test.dart` now proves discussion sends remain allowed while recovery is active, and `group_resume_recovery_test.dart` now proves the real `GroupConversationWired` sender path still sends discussion messages while blocking announcement-admin sends without leaving a stranded local bubble. |
| `RC-009` | Accepted | `pubsub_decryption_failure_test.go` now proves wrong-key, tampered-nonce, and malformed-payload failures emit diagnostics without any `group_message:received` event, while `go_bridge_client_test.dart` routes `group:decryption_failed` and `group:payload_parse_failed` into Flutter's `groupDiagnosticEventStream` without invoking the group message callback. |
| `RC-010` | Accepted | `go-mknoon/node/node_test.go` now proves bounded bursts emit `group:dispatcher_pressure` and `group:dispatcher_overflow` diagnostics with queue-depth, dropped-count, and last-event data, while `go_bridge_client_test.dart` proves overflow diagnostics reach Flutter's owned diagnostics stream and flow logs without invoking the group message callback. |
| `SV-004` | Accepted | `handle_incoming_group_message_use_case_test.dart` now proves same-`messageId` replays cannot rewrite an accepted row when timestamps are tampered or when the replay lands after removal/dissolve cutoffs, and `group_resume_recovery_test.dart` now proves a multi-page inbox replay with a tampered timestamp still materializes only one stored row. |
| `SV-005` | Accepted | `pubsub_decryption_failure_test.go` now proves wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload group envelopes emit rejection diagnostics without any `group_message:received` event, and `go_bridge_client_test.dart` keeps the owned Flutter diagnostics stream pinned for `group:decryption_failed`. |
| `SV-006` | Accepted | `pubsub_key_rotation_grace_test.go` now proves previous-epoch traffic emits `group_message:received` during grace and stays silent after grace expiry, while the existing `group_message_listener_test.dart` and `handle_incoming_group_message_use_case_test.dart` already pin the Flutter-visible receive-path materialization for any valid group message event. |
| `SV-007` | Accepted | `group_key_update_listener_test.dart` now proves competing same-generation key updates collapse to one stored key and the existing sequential `epoch 2 then epoch 3` proof keeps higher-epoch convergence explicit, while `send_group_message_use_case_test.dart` and `group_resume_recovery_test.dart` keep sending usable after rotation on the winning epoch. |
| `SV-011` | Accepted | `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `retry_failed_group_inbox_stores_use_case_test.dart` now pin stable begin/success/skip/error/timing flow-event names and required detail keys across the shipped group send, rejoin, drain, and retry owners. |
| `SV-012` | Accepted | `go-mknoon/node/node_test.go` now proves overflow diagnostics are emitted with dropped-count and queue-depth data, and `go_bridge_client_test.dart` proves `group:dispatcher_overflow` reaches Flutter's diagnostics stream and flow logs instead of remaining silent. |
| `RY-007` | Covered | `group_resume_recovery_test.dart` already proves the partitioned member misses split-window live delivery, replays the delayed backlog in cursor order after heal, and resumes later live delivery without duplicate visible rows. |
| `RY-010` | Accepted | `main.dart`, `startup_router.dart`, `handle_app_resumed.dart`, `prepare_notification_route_target_use_case.dart`, `group_list_wired.dart`, and `orbit_wired.dart` now carry full replay dependencies on supported paths, while `accept_pending_group_invite_use_case_test.dart` and `group_list_wired_test.dart` pin the repaired invite-accept drain with a real `GroupMessageListener` and `reactionRepo`. |
| `RY-011` | Accepted | `accept_pending_group_invite_use_case_test.dart` now proves invite acceptance drains backlog reactions when `reactionRepo` is supplied, and `group_list_wired_test.dart` proves the shipped accept flow persists the replayed message and reaction before the pending invite row disappears. |
| `RY-012` | Accepted | `accept_pending_group_invite_use_case_test.dart` now proves `bridgeError` keeps the group persisted, clears the pending invite row, and still stores the durable join event for replay even when live `group:publish` fails, `group_list_wired_test.dart` proves the shipped accept surface tells the user recovery is still catching up, and `invite_round_trip_test.dart` proves a later rejoin plus inbox drain converges without recreating the invite row or duplicating join history. |
| `RY-013` | Accepted | `group_offline_replay_envelope.dart` now stores only the approved replay wrapper plus ciphertext and nonce, and `go-mknoon/node/group_inbox_test.go`, `go-relay-server/group_inbox_test.go`, and `go-relay-server/backend_redis_test.go` now prove that opaque envelope survives request marshaling and cursor retrieval without exposing plaintext content. |
| `RY-014` | Accepted | `drain_group_offline_inbox_use_case_test.dart` now proves encrypted replay preserves quoted replies plus image, video, GIF, file, and audio attachments through the real drain path, while `group_resume_recovery_test.dart` keeps missed announcement replay, voice delivery, and post-rotation delivery readable after resume. |
| `RY-015` | Accepted | `group_resume_recovery_test.dart` now proves removed offline members drain the replayed removal, lose group access, and cannot send after resume while remaining members keep only the before-cutoff backlog, `group_info_wired_test.dart` proves voluntary leave persists a durable left-the-group event before cleanup, and `invite_round_trip_test.dart` proves rejoined members recover on the rotated epoch only. |
| `RY-016` | Accepted | `drain_group_offline_inbox_use_case_test.dart`, `group_resume_recovery_test.dart`, `rejoin_group_topics_use_case_test.dart`, `retry_failed_group_inbox_stores_use_case_test.dart`, `pending_message_retrier_upload_ordering_test.dart`, and the resume lifecycle tests now prove encrypted replay survives cursor continuation, multi-page drain, watchdog resume, sender-owned reaction add/remove replay retry, partition heal, and same-message dedupe without creating a degraded recovery owner. |
| `MD-005` | Partial | Executor evidence from 2026-04-30 confirms current repo behavior does not cover chunked media resume. `p2p_bridge_client.dart` sends whole-object `media:upload` payloads with `id`, `to`, `mime`, `filePath`, and optional `allowedPeers`, and whole-object `media:download` payloads with `id` and `outputPath` only. `upload_media_use_case.dart` encrypts and uploads one full file path; `download_media_use_case.dart` downloads one full blob, validates the completed encrypted hash/decrypt/plaintext, and deletes invalid or partial local files; `retry_incomplete_group_uploads_use_case.dart` retries whole `upload_pending` attachments by blob id. `go-mknoon/node/media.go` streams whole uploads with `io.Copy` and whole downloads with `io.CopyN`; `go-relay-server/media.go` stores only complete uploads and removes incomplete upload files. Passed adjacent whole-object/progress/integrity gates: `cd go-mknoon && go test ./node -run 'MediaUploadProgressReader\|IdleTimeoutReader' -v`; `cd go-relay-server && go test ./... -run 'Media\|GroupMedia' -v`; `flutter test --no-pub test/features/conversation/application/upload_media_use_case_test.dart`; `flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart`; `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart`. No current proof covers chunk manifests, per-chunk hashes, verified chunk reuse, same-peer or other-peer resume, progress without duplicated completed bytes, or corrupted-chunk redownload. `group-real-network-nightly` was fixture-blocked locally because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset. |
| `MD-011` | Covered | Tests-only closure on 2026-04-30. `group_media_fanout_test.dart` proves the post-removal future-media path: after C is removed and A/B advance to epoch 2, B receives and downloads A's future media while C has no message, descriptor/media row, pending download, `media:download`, `blob:decrypt`, epoch-2 key, subscription, or local content. `retry_incomplete_group_uploads_use_case_test.dart` proves retry upload `allowedPeers` and `group:inboxStore` `recipientPeerIds` are rebuilt from the post-removal member set and exclude C. `drain_group_offline_inbox_use_case_test.dart` proves a removed peer with only epoch 1 skips an epoch-2 future media replay before message/media/download/decrypt persistence. Go relay media ACL tests prove a peer omitted from `allowedPeers` cannot download a group blob. Focused Dart files, adjacent removal/UI tests, the tagged Go integration command, Go relay media ACL command, groups integration, `groups`, `completeness-check`, and `git diff --check` passed in the execution evidence. The untagged Go integration command is invalid because integration tests require `-tags integration`; `flutter test --no-pub test/features/groups` still has an unrelated `group_conversation_wired_test.dart:4114` failure; device/real-relay proof is supplemental and fixture-blocked until `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are set. |
| `MD-012` | Covered | MD-012 closure on 2026-04-30. `group_media_integrity_policy_test.dart` pins the quarantine status helpers and keeps quarantine, download retry, and upload retry ownership separate. `download_media_use_case_test.dart` proves unsafe descriptor, relay MIME, content hash, encryption/decrypt, missing decrypted file, plaintext size, and plaintext MIME/signature failures become `integrity_failed` without displayable local paths, while bridge-level blob-not-found remains `failed`. `group_conversation_screen_test.dart`, `media_grid_cell_test.dart`, and `audio_player_widget_test.dart` prove visual and voice rows show explicit `Media unavailable` UI, stable `Retry unavailable media` semantics, and no thumbnail/open/play affordance until verified. `letter_card_test.dart`, `group_conversation_wired_test.dart`, and `retry_incomplete_group_uploads_use_case_test.dart` prove incoming/read-only retry is a per-attachment `downloadMedia(... enforceGroupMediaPolicy: true)` repair path, not failed-message resend or incomplete-upload retry, and never calls `retryFailedGroupMessage`, `retryIncompleteGroupUploads`, `group:publish`, or `group:inboxStore` for download-only repair. `group_conversation_wired_test.dart` proves targeted repaired retry becomes `done` only after verification and failed repair stays quarantined, clears the unsafe local path, deletes the stale file, and does not open full-screen media. `group_media_fanout_test.dart` keeps tampered fake-network downloads quarantined before `done`. Focused MD-012 suites, groups integration, broad `test/features/groups`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. Device/real-relay proof is supplemental for this row and was unavailable in the host-side session. |
| `MD-014` | Partial | MD-014 targeted proof rerun on 2026-04-30 used configured `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and the supplied relay addresses. `./scripts/run_test_gates.sh group-real-network-nightly` passed, including the real CLI peer group recovery test, so the row is no longer blocked only by absent device/relay fixtures. GMAR-004 later fixed the stale simulator media fixture metadata without weakening group media integrity policy, and `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` passed after clean rebuild. GMAR-004 also accepted host screen/wired visible-state, reopen hydration, retry visibility, and signed offline inbox duplicate-enrichment proof. Missing closure evidence for the broader MD-014 row still includes current full discussion and announcement media/recovery matrix proof, relay outage/recovery and duplicate-prevention breadth, OS-state breadth, and a decision on the file dimension while MD-013 remains unsupported. |
| `EK-001` | Covered | EK-001 closure on 2026-04-30. `go-mknoon/node/protocol_version_test.go` now includes `TestSecureLibp2pChannelRequiredBeforeMknoonProtocols`, proving a deliberately insecure `libp2p.NoSecurity` host cannot connect to a production mknoon node over the raw TCP address, cannot open `ChatProtocol`, and leaves no connected insecure peer on either side. The test is payload-free, so invite, sync, media, group key, and publish payloads are never handed to mknoon protocol handlers over the insecure channel. Existing protocol tests keep secure mknoon nodes negotiating current chat protocol, rejecting unsupported chat protocol versions, and using `InboxProtocol` for group inbox store. Focused EK-001 protocol suite and broader adjacent Go node security/protocol slice passed. App-layer encryption, signatures, and storage-path privacy remain separate rows. |
| `EK-002` | Covered | EK-002 closure on 2026-04-30. `go-mknoon/node/pubsub_test.go` proves relay-visible group message and reaction envelopes omit protected plaintext while carrying encrypted ciphertext/nonce, `go-mknoon/node/group_inbox_test.go` proves group inbox-store request JSON preserves an opaque encrypted replay envelope and omits sensitive plaintext fragments, and `send_group_message_use_case_test.dart` now includes `EK-002 pending inbox retry stores encrypted replay without protected plaintext`, proving persisted pending inbox retry JSON plus the attempted `group:inboxStore` command carry a `group_offline_replay` encrypted envelope and omit protected message body, invite/private-state fragments, media encryption keys, and plaintext push previews. Focused Go, focused Flutter, broader storage-path Dart bundle, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. EK-001 transport security, EK-004 signatures, EK-005 future epochs, EK-012 replay protection, and EK-013 secure-storage deletion remain separate rows. |
| `EK-003` | Covered | EK-003 covered by `PREREQ-DEVICE-IDENTITY` on 2026-05-01. Production now has a first-class group member device roster: `GroupMemberDeviceIdentity`, migration `062_group_member_device_identities.dart`, DB helper/model/repository/fake persistence, config snapshots, invite/admission paths, key distribution/listener paths, live/offline message and reaction paths, fake-network harnesses, and Go envelope/config validation all carry device id, transport peer id, device signing key, ML-KEM/key-package material, status, and key-package id while preserving `GroupMember.peerId` as the member/account identity. Regression evidence proves valid bound devices are accepted and same-member unbound devices, signing-key mismatches, transport mismatches, wrong local invite recipients, wrong key-update recipients, and invalid replay senders fail before message/key/event-log/listener/notification/bridge side effects. Passed commands: model/invite domain block, migration/helper/full-chain block, invite admission block, key distribution/listener block, message/listener/offline replay block, fake-network integration block, Go envelope/device validator blocks, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Paired-iOS and real-relay proof were not required; Android paired proof remains fixture-blocked by missing `adb` and `emulator-5556`. |
| `EK-004` | Covered | EK-004 covered on 2026-05-02 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EK-004-plan.md`. Production files: `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, message/reaction/remove/retry/invite-accept/leave/dissolve/group-info sender call sites, direct key/audit/listener paths, and `go-mknoon/node/pubsub_test.go`. Current offline/pending/history replay envelopes are signed at generation and verified before decrypt/apply; unsigned legacy relay payloads, malformed/mismatched/invalid replay signatures, wrong sender/relay bindings, invalid history repair ranges, and pending-key repair replays fail closed before message, reaction, system/member/key/timeline, cursor, notification, receipt/read-state, or event-log mutation. Direct invite, invite revocation, welcome/key-package material embedded in invites, direct `group_key_update`, signed transition audit, local `group_created`, and Go live PubSub signature validation evidence are preserved. Evidence passed: focused EK004 Flutter bundle (`+16`), direct key/audit/remote-family selector (`+12`), local create/event-log (`+19`), invite wildcard (`+149`), key wildcard (`+49`), fake-network invite/resume/membership replay bundle (`+80`), Go invalid-signature selector for all shipped live event families, targeted format, scoped analyzer with info-only diagnostics, `groups` (`+103`), `completeness-check` (`712/712`), and `git diff --check`. `group_info_wired.dart` still has the documented pre-existing warning-only analyzer cluster and no analyzer errors. Real device/relay proof is supporting-only for EK-004 because the row closes on deterministic host/fake-network/Go replay-validation seams; full MLS semantics and separate account/device registry are not claimed. |
| `EK-005` | Covered | EK-005 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-FUTURE-EPOCH-KEY-REPAIR-plan.md`. Migration `063_group_pending_key_repairs`, `group_pending_key_repairs_db_helpers.dart`, `GroupPendingKeyRepairRepositoryImpl`, and `group_pending_key_repair_service.dart` add a durable deduped future/missing-key repair queue. Offline replay with a missing epoch now stores a pending placeholder, preserves encrypted replay JSON, emits a scoped repair request, retries after a saved key update, re-enters normal verified replay handling, replaces the placeholder with the decrypted row on success, and finalizes invalid or unrecoverable repairs idempotently as safe `undecryptable` text without plaintext, media downloads, duplicate rows, or endless retry loops. Commands relied on: RED focused drain test failed before production; migration/helper tests passed (`+4`); repository tests passed (`+2`); focused drain/key-listener/message-listener/UI/bridge tests passed (`+5`); full migration chain passed (`+6`); direct owner Flutter suites passed (`+178`, `+36`, `+49`); Go focused and owner regexes passed; `./scripts/run_test_gates.sh groups` passed (`+101`); `./scripts/run_test_gates.sh completeness-check` passed (`703/703`); `git diff --check` passed. Unknown future live epochs may still reject before normal Go delivery; recovery is through durable offline replay/key-arrival repair. |
| `EK-006` | Covered | EK-006 accepted on 2026-05-01. `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves the raw epoch policy: authorized previous-epoch traffic is accepted during grace, previous-epoch traffic is rejected after grace expiry, current-epoch traffic still accepts during grace, a removed/non-member sender using a valid previous-epoch envelope is rejected as `reject:non_member`, subscription handling decrypts previous-epoch traffic during grace, and subscription handling drops previous-epoch traffic after grace expiry without `group_message:received`. Flutter app-level proof covers the shipped UI/state outcome: `send_group_message_use_case_test.dart` rejects local stale sends before persistence or bridge publish; `handle_incoming_group_message_use_case_test.dart` accepts only pre-cutoff removed-sender messages and rejects at-cutoff/later replay without overwriting the accepted row; `drain_group_offline_inbox_use_case_test.dart` carries the removedAt cutoff across cursor pages; and `group_membership_smoke_test.dart` proves remaining peers accept only delayed pre-cutoff removed-sender envelopes while at-cutoff envelopes create no UI rows, plus a self-removed member cannot send after cleanup. Passed commands: focused Go EK-006 grace/expiry suite, focused handler removed-sender proof (`+3`), offline replay cutoff (`+1`), stale local send (`+1`), live fake-network cutoff (`+1`), self-removal send guard (`+1`), and `git diff --check`. Supporting real-network/device-lab/packet-capture proof remains supplemental and was not run. No first-class device identity, MLS commit semantics, or new transport cryptography is claimed. |
| `EK-007` | Partial | EK-007 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_scheduled_rotation_primitives`. Manual/app-triggered rotation continuity is proven by Go `TestGroupRotateKey_IncrementsEpoch` and `TestGroupGenerateNextKey_DoesNotMutateStoredKeyState`, Flutter `rotate_group_key_use_case_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, `group_key_update_listener_test.dart`, `send_group_message_use_case_test.dart`, `member_removal_integration_test.dart`, `invite_round_trip_test.dart`, and `group_resume_recovery_test.dart`. The row remains Partial because searches found no scheduled/periodic key rotation service, timer, policy, configuration, or background owner; therefore there is no row-specific scheduled-rotation proof that scheduled and manual rotations share the same monotonic distribution/promotion/send-binding contract. |
| `EK-008` | Open | EK-008 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_first_class_device_identity_model`, `missing_device_compromise_recovery_primitives`, and `missing_per_device_key_package_and_future_key_exclusion`. Adjacent evidence proves only fake-network same-peer device-local unsubscribe while preserving sibling delivery, member-scoped key rotation/distribution, member removal/leave future-key exclusion, key-update save/promotion ordering, and Go member-level sender/transport/public-key/signature binding. The row remains Open because no production model can identify or revoke only B2, no per-device key package or distribution roster exists, and no live/equivalent proof shows B2 excluded from future epoch updates/content while B1 and other members continue. |
| `EK-010` | Open | EK-010 closure attempt on 2026-04-30 is prerequisite-blocked by `missing_signed_commit_transition_model`, `missing_group_transition_event_log`, `missing_commit_replay_and_fork_protection`, and `missing_independent_state_verification_from_commits`. Adjacent evidence proves PubSub security-family signatures fail closed, metadata `configVersion`/`stateHash` tamper checks reject invalid updates, membership watermarks block stale rollback after restart, and rotation/key-update ordering remains green. The row remains Open because there is no durable signed commit or transition-event model for create/add/remove/role/metadata/key-rotation/recovery changes, no previous-state dependency or commit-chain hash, no local append-only/tamper-evident group event log, and no replay/fork protection over signed transition history. |
| `EK-011` | Covered | EK-011 covered by `PREREQ-WELCOME-KEY-PACKAGE` Executor and recovery evidence on 2026-05-01. `GroupWelcomeKeyPackage` now models and validates package id/material/hash, recipient member/device/transport/ML-KEM binding, invite id, group id, epoch, issue/expiry, and schema version; `GroupInvitePayload` and `GroupInvitePolicy` include the package in the signed canonical encrypted invite payload. Send rejects weak package material before signing/encryption. Incoming store, direct handle, and pending accept reject stale, malformed, tampered, wrong-recipient, wrong-device, wrong-transport, wrong-package, and weak packages before pending/group/key/join/mailbox/publish/listener/notification/bridge side effects. Migration/helper/repository wiring adds durable package tombstones; successful accept records the tombstone after materialization, replay under a changed invite id fails before state, and file-backed repository tests prove close/reopen survival. The recovery pass adds `defaultGroupWelcomeKeyPackageIdForDevice`, wires `ownKeyPackageId` through `main.dart`, `GroupListWired`, and `OrbitWired`, and proves valid first-class package invites store/accept through production listener and UI pending-accept paths while a wrong local package id still rejects. Evidence passed: focused welcome-package owner suite (`120` tests), recovery listener/UI focused tests (`3` + `1` + `1` tests), invite wildcard (`117` tests), targeted analyzer, groups gate (`101` tests), completeness-check (`706/706`), and `git diff --check`. |
| `EK-012` | Covered | EK-012 covered on 2026-05-01 by `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-PREREQ-REMOTE-EVENT-FAMILIES-plan.md` plus prior replay prerequisites. The final missing event-family blockers are closed by trusted-private encrypted system-event support for `member_banned`, `member_unbanned`, and `group_message_deleted`: `trusted_private_group_system_event.dart` parses canonical tombstone fields, `GroupMessageListener` routes those families through existing device binding, authorization, signed transition audit/event-log integration, deterministic tombstone/timeline rows, duplicate replay idempotency, stale ban-after-unban/rejoin protection, and stale/wrong-group/newer-message delete protection. Go invalid-signature coverage now includes those new families. Prior prerequisites keep welcome/key-package tombstones, signed system-transition replay, durable receipt replay, future/missing-key repair replay, message/reaction replay, and invite replay covered. Evidence passed: listener PREREQ tests (`+3`), offline replay PREREQ test (`+1`), Go invalid-signature regex, `groups`, `completeness-check`, and `git diff --check`; targeted analyzer reports only documented pre-existing warning debt in `group_message_listener.dart` and no analyzer errors. EK-004 is covered separately for complete offline replay signature-equivalence. |
| `EK-013` | Covered | EK-013 closed on 2026-04-30. `GroupRepositoryImpl.saveKey` now enforces a latest-plus-previous group-key retention policy: saving generation 3 after generations 1 and 2 keeps generations 2 and 3, removes generation 1 from SQLCipher `group_keys`, and deletes the matching shared push `SecureKeyStore` mirror. `removeAllKeys` still clears all group keys and secure-store mirrors, `mirrorAllKeysToSecureStore` still mirrors approved persisted rows, and `InMemoryGroupRepository` follows the same bounded retention behavior for fake-backed group tests. Focused repository, rotation/key-update, and Go bridge/node validator gates passed. SQLCipher `group_keys` remains the approved app-local encrypted store for current/previous group-operation keys, while backup/export product policy, per-device key packages, debug export redaction, and memory wiping remain separate rows. |
| `EK-014` | Covered | EK-014 closed on 2026-04-30. `contact_safety_number.dart` builds stable grouped safety numbers from peer id plus Ed25519 and optional ML-KEM identity keys, and `group_member_identity_safety.dart` compares current group-member keys with the saved contact keys. `group_info_wired.dart`, `group_info_screen.dart`, and `group_member_row.dart` now surface `Identity changed`, `Current safety`, and `Saved safety` in the member list when saved and current identity keys differ. `contact_safety_number_test.dart`, `group_info_screen_test.dart`, and `group_info_wired_test.dart` prove deterministic/change-sensitive safety numbers, changed-key warnings, current/saved safety-number display, matching-key no-warning behavior, and no false warning without comparable saved contact/current key material. Focused and combined EK-014 gates, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. First-class per-device verification remains EK-003/EK-008 scope. |
| `ID-003` | Covered | `group_messaging_smoke_test.dart` proves non-friend members can exchange discussion traffic once they share membership, and the `group_test_user.dart` harness avoids contact-repo shortcuts. |
| `ID-008` | Covered | `group_membership_smoke_test.dart`, `invite_round_trip_test.dart`, and `group_message_listener_test.dart` together cover duplicate re-add, duplicate invite, and stale membership replay de-duplication. |
| `ID-009` | Covered | `handle_incoming_group_invite_use_case_test.dart` proves avatar metadata persistence, and the accept path reuses the same payload materialization contract before the feed refresh assertions consume it. |
| `MM-008` | Covered | `send_group_message_use_case_test.dart` proves pending publish-success rows promote only through the owned inbox-store completion path. |
| `MM-010` | Covered | `group_conversation_wired_bg_task_test.dart` directly covers discussion and announcement sends across lock, route unmount, and zero-peer fallback branches. |
| `MM-013` | Covered | `group_resume_recovery_test.dart` covers media recovery through the real group sender path, and the integration harness keeps member transport independent from friendship edges. |
| `RC-006` | Covered | `handle_incoming_group_message_use_case_test.dart`, `group_message_listener_test.dart`, and `group_conversation_wired_test.dart` together prove row upsert, shared media download joining, and scroll preservation without duplicate rows. |
| `SV-008` | Covered | `group_membership_smoke_test.dart` and `invite_round_trip_test.dart` cover concurrent role/member conflict convergence plus rotated re-invite recovery. |
| `SV-010` | Accepted | `bridge_group_helpers_test.dart` already pins the canonical `/mknoon/group/...` bridge response and join payload contract, and `create_group_use_case_test.dart` now proves the creator fallback and persisted group row stay on that same namespace when `topicName` is omitted. |

### Explicit Residual Follow-Up (2026-04-13)

- None for sender-owned reaction replay durability after Report `70`:
  `send_group_reaction_use_case_test.dart`,
  `remove_group_reaction_use_case_test.dart`,
  `retry_failed_group_inbox_stores_use_case_test.dart`,
  `announcement_happy_path_test.dart`, and
  `group_resume_recovery_test.dart` now prove exact-payload staging plus
  retry/resume convergence for reaction add/remove.

### Shared Prerequisite Sessions

| Session | Closure state | Concrete repo evidence |
|---------|---------------|------------------------|
| `PREREQ-GROUP-OFFLINE-REPLAY` | Accepted | `group_offline_replay_envelope.dart` now materializes opaque encrypted replay envelopes on the Flutter side, `go-mknoon/node/group_inbox_test.go` plus `go-relay-server/group_inbox_test.go` and `backend_redis_test.go` prove those envelopes stay opaque across node and relay storage/retrieval, and the replay batch plus invite/rejoin/retry lifecycle batches passed with the new contract in place. |
| `PREREQ-GROUP-PROOF-HARNESS` | Accepted | `go-mknoon/node/group_security_harness_test.go` now centralizes raw-envelope mutation, local-node connect/publish, event wait, and grace-fixture helpers, while `pubsub_decryption_failure_test.go` and `pubsub_key_rotation_grace_test.go` now reuse that seam directly for later `RC-009` / `SV-004..007` closure work. |
| `PREREQ-GROUP-DISPATCHER-OVERFLOW` | Accepted | `go-mknoon/node/event_dispatcher.go` now surfaces dispatcher pressure/overflow diagnostics, `go-mknoon/node/node_test.go` proves those signals carry queue-depth and dropped-count data under burst load, and `go_bridge_client_test.dart` proves `group:dispatcher_overflow` reaches Flutter diagnostics and flow logs without pretending to be a delivered group message. |

## 0A. 2026-04-12 Deployed-Relay Acceptance

- Full suites green: Flutter host-side `/private/tmp/flutter_full_suite_20260412/flutter_test_dir.log` (`02:53 +5492 ~5: All tests passed!`), `go-mknoon` `/tmp/go-mknoon-full-suite.log`, and relay `/tmp/go-relay-server-full-suite.log`.
- Live-lane passes green: Android background reconnect after bounded local build-state reset `/private/tmp/acceptance_20260412/background_reconnect_android_rerun1.log`; transport E2E `/private/tmp/acceptance_20260412/lane2.log`; WiFi relay fallback smoke after the truthful direct-transport contract fix `/private/tmp/acceptance_20260412/lane3_rerun.log`; media stable-ID smoke `/private/tmp/acceptance_20260412/lane4.log`; group recovery E2E `/private/tmp/acceptance_20260412/lane5.log`; soak E2E `/private/tmp/acceptance_20260412/lane6.log`; notification-open UI smoke on the primary iOS pair `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`; real multi-device `MD-004` on the primary iOS pair `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`.
- Truthful multi-relay skips: `/private/tmp/acceptance_20260412/lane7.log` and `/private/tmp/acceptance_20260412/lane8.log` both ended `All tests skipped.` because no two-relay `MKNOON_RELAY_ADDRESSES` environment was configured. They are not counted as multi-relay proof.

## 0B. Report 85 Group Onboarding And Crypto Coverage (2026-04-29)

Report 85 (`Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`) added or tightened the following group-chat test evidence. These rows are intentionally classified by evidence type so fake-network/app-boundary coverage is not confused with paired-simulator or relay-lab proof.

| Area | Closure state | Concrete repo evidence |
|------|---------------|------------------------|
| New-member discussion media/no-backfill | Covered at fake-network/app layer; configured simulator/reopen proof accepted; broader matrix residuals remain | `group_new_member_onboarding_test.dart` proves Bob receives only post-join text/image/video/voice, preserves media descriptors, triggers downloads, and keeps pre-join history out. GMAR-003 adds Bob/Charlie multi-new-member proof where both independently download Alice's same post-join image/video/voice while pre-join text/media rows, attachment rows, pending downloads, and pre-join media download calls remain absent. GMAR-004 adds configured simulator visible video/voice proof plus host reopen hydration and retry/offline duplicate evidence. |
| Multi-add epoch convergence | Covered at fake-network/app layer | `group_new_member_onboarding_test.dart` proves Bob and Charlie converge on the same key epoch and receive the same post-add message. |
| Add/send boundary | Covered at fake-network/app layer | `group_new_member_onboarding_test.dart` pins the current contract: a staged but unsubscribed new member misses the racing message and receives the first post-subscription message exactly once. |
| New-member reactions and quoted replies | Covered at fake-network/widget layer | `group_new_member_onboarding_test.dart` proves post-join reaction fan-out without pre-join reaction state and renders `Message unavailable` for a post-join quote whose parent predates the join. |
| Announcement new-reader media/no-backfill | Covered at fake-network/app layer; simulator residual remains | `announcement_new_reader_onboarding_test.dart` proves post-join admin image/video/voice reaches a newly-added reader with descriptors and no pre-join admin post. |
| Integrated real crypto first-add/re-add | Covered at real Go-bridge app boundary; live GossipSub residual remains | `group_real_crypto_onboarding_test.dart` generates real bridge identities/ML-KEM keys, accepts encrypted invites through the app handler, decrypts first-add and re-add group ciphertext, and proves retained old key material cannot decrypt the current epoch. |
| Existing/newly-added/non-creator media fan-out | Covered at fake-network/app layer; configured simulator render proof accepted; live GossipSub/final matrix residuals remain | GMAR-002 tightened `group_media_fanout_test.dart` on 2026-05-02 so existing Bob and Charlie each independently complete Alice's image/video/voice downloads with matching message ids, attachment metadata, `done` status, local paths, and exact per-recipient download calls; the same suite proves one recipient's forced download failure remains observable while the other recipient succeeds. GMAR-003 adds newly-added Bob media to Alice/Charlie and existing non-creator Charlie media to Alice/Bob, both with completed downloads, sender identity, key epoch, metadata, and exact per-recipient download calls. GMAR-004 accepts the configured simulator preview/playback proof for representative visible video/voice rows. |
| Foreground push media drain | Covered by direct foreground-router/inbox integration; OS-state residual remains | `foreground_group_push_drain_test.dart` now covers targeted group media drain, descriptor preservation, one download trigger, and no duplicate row/notification. |
| Stale removed-group notification denial | Covered host-side; paired simulator residual remains | `resolve_group_notification_route_target_use_case_test.dart` covers stale removed-group route denial after local cleanup, and `group_message_listener_test.dart` proves self-removal suppresses later group notifications. |
| Paired group-smoke criteria | Covered by host criteria tests; configured paired run residual remains | `routing_smoke_group_criteria_test.dart` and `routing_smoke_group_criteria.dart` require receiver-visible G2/G4/G5/G7/G8 evidence instead of sender-only or pending results. |
| Retry/media recovery host safety net | Revalidated host-side; configured simulator UI proof accepted; broader device-lab residual remains | `retry_incomplete_group_uploads_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `group_conversation_screen_test.dart` cover incomplete-upload retry, failed-message retry, and failed-media row retry/delete controls. GMAR-004 adds configured simulator visible video/voice proof, wired reopen hydration, and signed offline inbox duplicate-enrichment coverage. |
| Relay fixture closure guard | Gate wiring covered; configured relay run required for pass | `multi_relay_failover_test.dart` now supports `MKNOON_REQUIRE_MULTI_RELAY=true`; `./scripts/run_test_gates.sh group-real-network-nightly` requires `FLUTTER_DEVICE_ID` and at least two relay addresses. |
| Partition/heal durable inbox recovery | Covered for fake-network durable-inbox contract; real network residual remains | `group_resume_recovery_test.dart` now stages three missed split-window messages across cursor-ordered durable inbox pages and proves post-heal live delivery resumes. |
| Same-account host convergence | Covered at host fake-network layer; real device residual remains | `group_multi_device_convergence_test.dart` remains the same-account oracle for sent history, membership, mute, unread, and notification locality; `group_multi_device_policy_test.dart` pins composer drafts as device-local state. |
| Go membership-event signature guard | Covered at Go envelope-validator layer | `pubsub_test.go` adds forged `members_added` signature rejection while accepting the same payload when signed by the real admin. |

## 0C. MD-001 Media MIME Safety Closure (2026-04-30)

MD-001 adds `test/core/media/group_media_mime_policy_test.dart` as the policy anchor and extends the existing upload, download, send, retry, live receive, replay, listener, and media-grid tests named in the row crosswalk. The focused MD-001 direct suite passed with `+243`, `group_media_fanout_test.dart` passed with `+2`, `flutter test --no-pub test/features/groups` passed with `+973`, `flutter test --no-pub test/features/groups/integration` passed with `+112`, `./scripts/run_test_gates.sh groups` passed with `+93`, and `./scripts/run_test_gates.sh completeness-check` passed. `SMOKE-GAP-05` maps to that evidence bundle; it is not a shell target.

## 0D. MD-002 Media Size Safety Closure (2026-04-30)

MD-002 adds `test/core/media/group_media_size_policy_test.dart` as the policy anchor and extends the existing upload, send, retry, live receive, encrypted replay, listener, foreground push, download, media-grid, wired composer, and fake-network fanout tests named in the row crosswalk. Focused direct suites passed, `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed after the unqualified command required device selection, `flutter test --no-pub test/features/groups` passed with `+985`, `flutter test --no-pub test/features/groups/integration` passed with `+113`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `690/690` classified, and `git diff --check` passed. `SMOKE-GAP-05` maps to that evidence bundle; it is not a shell target.

## 0E. MD-003 Media Integrity Closure (2026-04-30)

MD-003 adds `test/core/media/group_media_integrity_policy_test.dart` and extends the model, migration, DB helper, upload, download, send, retry, live receive, encrypted replay, listener, foreground push, feed, group conversation, media-grid, audio, and fake-network fanout tests named in the row crosswalk. Focused direct suites passed with `+435`, `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `+4`, `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` passed with `+7`, `flutter test --no-pub test/features/groups` passed with `+991`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, and `./scripts/run_test_gates.sh completeness-check` passed with `692/692` classified. The plan-listed `feed_wired_test.dart` focus target is not a valid MD-003 signal in this dirty tree because it fails to compile in unrelated `orbit_wired.dart` missing a `repairPending` switch case; narrower feed application/widget MD-003 tests passed. Thumbnail closure is explicit: group code has no remote thumbnail blob/path display surface, optional thumbnail hashes validate when present, and generated thumbnails derive only from verified content. `SMOKE-GAP-05` maps to this evidence bundle; it is not a shell target.

## 0F. MD-004 Media Key Separation Closure (2026-04-30)

MD-004 adds per-object group media encryption metadata to `MediaAttachment`, migration 059, DB helpers, upload and download use cases, send/receive/retry/listener paths, foreground push drain, fake-network fanout, and onboarding/resume integrations. The proof-first regression failed before implementation because group media lacked `encryptionKeyBase64`/`encryptionNonce` and did not encrypt before relay upload. The final contract generates a fresh key/nonce per group media object, uploads encrypted bytes, computes `contentHash` over the encrypted blob, carries decrypt metadata inside the encrypted group message/replay descriptor, verifies encrypted hash before decrypt, validates plaintext MIME/size after decrypt, and rejects wrong-key/cross-object decrypt attempts before display. Focused MD-004 suites passed, required fanout/onboarding/resume/foreground integrations passed, `flutter test --no-pub test/features/groups` passed with `+993`, `flutter test --no-pub test/features/groups/integration` passed with `+114`, `./scripts/run_test_gates.sh groups` passed with `+93`, `./scripts/run_test_gates.sh completeness-check` passed with `693/693` classified, and `git diff --check` passed. `SMOKE-GAP-05` maps to this evidence bundle; it is not a shell target.

## 0G. MD-011 Removed-Member Future Media Closure (2026-04-30)

MD-011 is a tests-only closure. `group_media_fanout_test.dart` proves live post-removal future media reaches remaining B and not removed C after rotation to epoch 2; C has no descriptor, message, media row, pending download, `media:download`, `blob:decrypt`, epoch-2 key, subscription, or local decrypted content. `retry_incomplete_group_uploads_use_case_test.dart` proves retry media `allowedPeers` and inbox `recipientPeerIds` exclude removed C, while `drain_group_offline_inbox_use_case_test.dart` proves C with only epoch 1 cannot decode or persist epoch-2 future media replay. Go relay media ACL coverage proves omitted peers cannot download group blobs. The invalid untagged Go integration command is accepted as a plan-command defect because the test file is tagged `//go:build integration` and the tagged command passed. `flutter test --no-pub test/features/groups` still fails in unrelated `group_conversation_wired_test.dart:4114`; the named `groups` gate passed. Device/real-relay proof is supplemental and remains fixture-blocked until `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are configured.

## 0H. MD-012 Unsafe Media Quarantine And Retry UI Closure (2026-04-30)

MD-012 closes the unsafe media quarantine UI path. `integrity_failed` is the accepted quarantine status for unsafe group media, while bridge-level missing blobs stay `failed`. Download policy now quarantines unsafe descriptor, relay MIME, content hash, encryption/decrypt, missing decrypted file, plaintext size, and plaintext MIME/signature failures without leaving displayable local bytes. Visual and voice rows render explicit `Media unavailable` UI with stable `Retry unavailable media` semantics and no thumbnail/open/play affordance until verification succeeds. Incoming/read-only retry is scoped to per-attachment `downloadMedia(... enforceGroupMediaPolicy: true)` repair and does not call failed-message resend, incomplete-upload retry, `group:publish`, or `group:inboxStore`. Focused MD-012 suites, `group_media_fanout_test.dart`, `test/features/groups/integration`, broad `test/features/groups`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. Device/real-relay proof is supplemental and remains outside this host-side row closure.

## 0I. MD-014 Simulator Media Matrix Targeted Recheck (2026-04-30)

MD-014 remains Partial. The targeted recheck used `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and the supplied `MKNOON_RELAY_ADDRESSES`; `./scripts/run_test_gates.sh group-real-network-nightly` passed, including the real CLI peer group recovery test. GMAR-004 later fixed the configured simulator media proof by adding truthful fixture content hashes and encryption metadata, and `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` passed after clean rebuild. The configured video/voice render proof is no longer an open MD-014 blocker. Remaining closure evidence still includes the full discussion/announcement image/video/GIF/voice/file matrix, OS-state breadth, relay outage/recovery and duplicate-prevention breadth, and MD-013 file-dimension scope reconciliation.

## 0I-a. Targeted Evidence/Gate Recheck Summary (2026-04-30)

Rows rechecked at this earlier evidence-gate pass: GL-008, LP-002, LP-006, LP-007, LP-011, LP-013, IJ-010, EK-006, and MD-014. No target row moved to Covered during that pass; GL-008, LP-002, LP-013, IJ-010, and EK-006 moved to Covered later through their row-owned session plan evidence recorded in the row-closure crosswalk above.
The remaining rows LP-007 and LP-011 kept their existing Partial evidence with focused direct gates passing and exact live/raw/device proof still missing. LP-006 is reclassified to implementation-ready/needs code-and-test follow-up because its direct zero-peer publish proof is red. At this earlier pass, MD-014 was reclassified to implementation-ready because configured real-network proof passed but configured simulator media rendering proof failed; GMAR-004 later accepted that configured simulator proof, leaving only the broader MD-014 matrix residuals listed above.

## 0J. EK-001 Secure Libp2p Channel Closure (2026-04-30)

EK-001 closes with a Go host-level transport-security proof. `TestSecureLibp2pChannelRequiredBeforeMknoonProtocols` starts a production mknoon node through `Node.Start`, starts a `libp2p.NoSecurity` host, restricts the attempt to the mknoon node's raw TCP address, and proves the insecure host cannot connect or open `ChatProtocol`; both peers also report no retained insecure connection. The test sends no group payload or secret, so failure occurs before invite, sync, media, or publish handling. The focused EK-001 protocol command and broader adjacent Go node security/protocol slice passed. EK-002, EK-004, EK-005, and other app-layer cryptographic rows remain separate.

## 0K. EK-002 Storage-Path Privacy Closure (2026-04-30)

EK-002 closes with infrastructure-visible payload proof across live relay, mailbox/inbox-store, and persisted retry storage paths. Go PubSub tests prove live group message and reaction envelopes expose only encrypted ciphertext/nonce while protected plaintext remains decryptable only with the group key. Go inbox-store tests prove mailbox request JSON preserves an opaque encrypted replay envelope and omits sensitive plaintext. The new Flutter retry test keeps `group.encrypt` opaque, forces inbox-store failure, and proves both persisted pending retry JSON and the attempted `group:inboxStore` command omit protected message body, invite/private-state fragments, media encryption key material, and plaintext push previews while carrying a `group_offline_replay` envelope. Focused Go, focused Flutter, broader storage-path Dart bundle, `groups`, `completeness-check`, and `git diff --check` passed. Signature, future-epoch, replay-protection, transport-security, and secure-storage rows remain separate.

## 0L. GIS-001 Local Group Invite Delivery Status Closure (2026-05-07)

GIS-001 closes local, backward-compatible invite delivery status tracking for
group creation/add-member flows and Group Info. Evidence covers migration `067`,
DB helper upsert/load/update/delete semantics, repository projection including
legacy `unknown`, direct invite `queued` mapping for inbox fallback,
create-flow `needs_resend` and `cannot_send` status recording, `member_joined`
to `joined`, Group Info status badges, and manual resend without duplicate
membership publication. Accepted gates: all direct
GIS-001 persistence/application/presentation tests, `invite_round_trip_test.dart`,
focused groups application/presentation regressions, contact-request
integration, `baseline`, `groups`, device-pinned `transport`,
`completeness-check` (`730/730`), and `git diff --check`. Protocol ACKs,
delivery receipts, `members_added` changes, group invite wire-format changes,
and key-format changes remain out of scope.

---

## 1. Domain Layer

### 1.1 GroupModel
**File:** `test/features/groups/domain/models/group_model_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupModel` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | GroupType enum converts correctly | Enum mapping |
| | GroupRole enum converts correctly | Enum mapping |
| | copyWith creates new instance with updated fields | Immutable update |

### 1.2 GroupMessage
**File:** `test/features/groups/domain/models/group_message_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMessage` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | round-trip preserves quoted_message_id | Quoted reply persistence |
| | isIncoming bool correctly converts from int | DB bool mapping |
| | toMap converts isIncoming bool to int | DB bool mapping |
| | media defaults to empty list | Default state |
| | can be constructed with media attachments | Media construction |
| | copyWith preserves and replaces media | Immutable update |
| | copyWith preserves and replaces quotedMessageId | Immutable update |

### 1.3 GroupMember
**File:** `test/features/groups/domain/models/group_member_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMember` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | MemberRole enum converts correctly | Enum mapping |
| | equality based on groupId and peerId | Value equality |
| | config JSON preserves joined interval for invite replay | Invite/config replay keeps membership interval |

### 1.4 GroupInvitePayload
**File:** `test/features/groups/domain/models/group_invite_payload_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInvitePayload` | toInnerJson serializes all required fields | Serialization |
| | fromInnerJson round-trips with toInnerJson | Round-trip |
| | toJson wraps payload in v1 envelope with type group_invite | v1 envelope construction |
| | fromJson parses v1 group_invite envelope | v1 envelope parsing |
| | fromJson returns null for chat_message type | Type guard |
| | buildEncryptedEnvelope produces v2 group_invite envelope | v2 envelope construction |
| `fromInnerJson returns null for missing required fields` | returns null when groupId is missing | Missing field guard |
| | returns null when groupKey is missing | Missing field guard |
| | returns null when groupConfig is missing | Missing field guard |
| | returns null when input is not valid JSON | Malformed input guard |
| `parseEncryptedEnvelope` | parses v2 group_invite envelope | v2 envelope parsing |
| | returns null for v2 chat_message (wrong type) | Type guard |
| | returns null for v1 group_invite | Version guard |
| | returns null for garbage JSON | Malformed input guard |
| | returns null when encrypted block is missing kem/ciphertext/nonce | Missing field guard |

### 1.5 GroupKeyInfo
**File:** `test/features/groups/domain/models/group_key_info_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupKeyInfo` | fromMap/toMap round-trip preserves all fields | DB round-trip |
| | equality based on groupId and keyGeneration | Value equality |

### 1.6 GroupMessagePayload
**File:** `test/features/groups/domain/models/group_message_payload_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupMessagePayload` | fromJson/toJson round-trip preserves all fields | Wire round-trip |
| | toJson omits null optional fields | Sparse serialization |

### 1.7 GroupReactionPayload
**File:** `test/features/groups/domain/models/group_reaction_payload_test.dart`

| Test | What it covers |
|------|----------------|
| round-trips add reaction | Serialization round-trip |
| round-trips remove reaction | Remove action round-trip |
| preserves multi-codepoint emoji | Unicode emoji handling |
| returns null for invalid JSON | Malformed input guard |
| returns null for missing fields | Missing field guard |
| toMessageReaction creates valid model | Model conversion |

### 1.8 PendingGroupInvite
**File:** `test/features/groups/domain/models/pending_group_invite_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingGroupInvite` | fromPayload derives preview fields and expiry | Factory construction |
| | fromMap/toMap round-trip preserves fields | DB round-trip |
| | isExpiredAt returns true on or after expiry | Expiry logic |

### 1.9 GroupBacklogRetentionPolicy
**File:** `test/features/groups/domain/models/group_backlog_retention_policy_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `group backlog retention policy` | uses a 7 day retention window | Policy constant |
| | cutoff helper subtracts the retention window in UTC | Cutoff calculation |

### 1.10 GroupMembershipLimitPolicy
**File:** `test/features/groups/domain/models/group_membership_limit_policy_test.dart`

| Test | What it covers |
|------|----------------|
| pins the repo-owned max group size contract at 50 members | Limit constant |
| remaining slots counts total members including the creator | Slot counting |
| overflow count stays zero at the limit and grows past it | Overflow detection |
| ensureWithinGroupMembershipLimit throws with overflow metadata | Enforcement |

### 1.11 GroupMultiDevicePolicy
**File:** `test/features/groups/domain/models/group_multi_device_policy_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `group multi-device policy` | shares only joined-device group-authoritative state | Shared state scope |
| | keeps local installation state device-specific | Local state scope, including composer drafts |
| | shared and device-local helpers stay aligned with the mapping | Helper alignment |

### 1.12 GroupRepositoryImpl
**File:** `test/features/groups/domain/repositories/group_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Groups` | saveGroup and getGroup round-trip | Persistence round-trip |
| | getAllGroups returns all groups | List query |
| | saveGroup and getGroup preserve announcement type through DB mapping | Announcement type |
| | updateGroup changes fields | Field update |
| | saveGroup and getGroup round-trip membership watermark | Watermark persistence |
| | saveGroup and getGroup round-trip metadata fields | Metadata persistence |
| | saveGroup and getGroup round-trip mute state | Mute persistence |
| | saveGroup and getGroup round-trip dissolved state | Dissolve persistence |
| | saveGroup and getGroup round-trip backlog retention state | Retention persistence |
| | deleteGroup removes the group | Deletion |
| | archiveGroup and unarchiveGroup work | Archive toggle |
| | getActiveGroups excludes archived | Active filter |
| `Members` | saveMember and getMember round-trip | Member persistence |
| | saveMember and getMember preserve permission overrides | Permission override persistence |
| | getMembers returns all members for group | Member list |
| | updateMemberRole changes the role | Role update |
| | removeMember and removeAllMembers work | Member deletion |
| `Keys` | saveKey and getLatestKey round-trip | Key persistence |
| | getKeyByGeneration returns correct key | Key lookup |
| | removeAllKeys clears all keys for group | Key cleanup |

### 1.13 GroupMessageRepositoryImpl
**File:** `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `saveMessage and getMessage` | round-trip preserves all fields | Persistence round-trip |
| | round-trip preserves quotedMessageId | Quoted reply |
| | returns null for non-existent | Missing record |
| `pause recovery` | transitionSendingToFailed transitions outgoing sending rows | Pause recovery |
| `getMessagesPage` | returns messages in chronological order | Sort order |
| | respects limit parameter | Pagination |
| `getLatestMessage` | returns null when no messages | Empty state |
| | returns the most recent message | Latest query |
| | getGroupThreadSummaries returns latest rows and zero defaults | Thread summary |
| | getGroupThreadSummaries preserves latest quotedMessageId | Thread quote |
| `updateMessageStatus` | updates the status field | Status mutation |
| `Section 1 recovery methods` | loads failed outgoing group messages | Failure query |
| | recovers stuck sending messages older than threshold | Stuck recovery |
| `getMessageCount` | returns correct count | Count query |
| `getUnreadCount` | counts only unread incoming messages | Unread filter |
| `getTotalUnreadCount` | counts across all groups | Cross-group count |
| `markAsRead` | marks unread incoming messages as read | Read marking |
| | does not mark outgoing messages | Direction guard |
| `deleteMessage` | removes the message | Message deletion |
| | does not affect other messages | Isolation |
| `existsByContent` | returns true for exact match | Content dedup |
| | returns false when no match exists | Negative case |
| | returns false for different sender | Sender discrimination |
| | returns false for different text | Text discrimination |
| | returns false for different timestamp | Timestamp discrimination |
| | does not match across groups | Group isolation |

### 1.14 PendingGroupInviteRepositoryImpl
**File:** `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingGroupInviteRepositoryImpl` | savePendingInvite and getPendingInvite round-trip | Persistence round-trip |
| | getPendingInvites orders newest first | Sort order |
| | deleteExpiredPendingInvites removes expired rows only | Expiry cleanup |
| | saveRevokedInvite and getRevokedInvite round-trip | Revocation tombstone persistence |
| | deleteExpiredRevokedInvites removes expired revocations only | Revocation cleanup |
| | saveConsumedInvite and getConsumedInvite round-trip | Consumption tombstone persistence |
| | deleteExpiredConsumedInvites removes expired consumptions only | Consumption cleanup |

### 1.15 GroupInviteDeliveryAttemptRepositoryImpl
**File:** `test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`

| Test | What it covers |
|------|----------------|
| round-trips all persisted invite delivery statuses | `sent`, `queued`, `needs_resend`, `cannot_send`, and `joined` repository persistence |
| projects no-row legacy members as unknown | Legacy/pre-migration compatibility |
| maps helper rows without UI logic | Repository row mapping and `lastError` preservation |

---

## 2. Data Layer (DB Helpers)

### 2.1 Groups DB Helpers
**File:** `test/core/database/helpers/groups_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroup` | inserts a new group | Insert |
| `dbLoadAllGroups` | returns all groups ordered by created_at DESC | List + sort |
| `dbLoadGroup` | returns null for non-existent group | Missing record |
| | returns group when it exists | Lookup |
| `dbUpdateGroup` | updates group fields | Field update |
| `dbDeleteGroup` | deletes a group | Deletion |
| `dbCountGroups` | returns correct count | Count |
| `dbArchiveGroup` | sets is_archived to 1 and sets archived_at | Archive |
| `dbUnarchiveGroup` | sets is_archived to 0 and clears archived_at | Unarchive |
| `dbLoadActiveGroups` | returns only non-archived groups | Active filter |

### 2.2 Group Messages DB Helpers
**File:** `test/core/database/helpers/group_messages_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupMessage` | inserts a new message | Insert |
| `dbLoadGroupMessagesPage` | returns empty list for no messages | Empty state |
| | returns messages in chronological (ASC) order | Sort order |
| | respects limit parameter | Pagination |
| `dbLoadAllGroupMessages` | returns only messages for the given group | Group filter |
| `dbLoadLatestGroupMessage` | returns null when no messages | Empty state |
| | returns the most recent message | Latest query |
| `dbLoadGroupMessage` | returns null for non-existent message | Missing record |
| | returns message when it exists | Lookup |
| | round-trips quoted_message_id | Quoted reply |
| `dbUpdateGroupMessageStatus` | updates status field | Status mutation |
| `dbCountGroupMessages` | returns correct count for a group | Count |
| `dbCountUnreadGroupMessages` | counts only unread incoming messages for a group | Unread filter |
| `dbCountTotalUnreadGroupMessages` | counts across all groups | Cross-group count |
| `dbMarkGroupMessagesAsRead` | marks unread incoming messages as read | Read marking |
| `dbDeleteGroupMessage` | deletes a single message | Deletion |

### 2.3 Group Messages DB Helpers (Sending)
**File:** `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`

| Test | What it covers |
|------|----------------|
| dbTransitionGroupSendingToFailed bulk transitions outgoing rows | Bulk transition |

### 2.4 Group Messages DB Helpers (Reliability)
**File:** `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `migration 041` | adds wire_envelope column | Schema migration |
| | adds inbox_stored column with default 0 | Schema migration |
| | adds inbox_retry_payload column | Schema migration |
| | is idempotent | Migration safety |
| | preserves existing rows | Data preservation |
| `dbLoadStuckSendingGroupMessages` | returns empty list when no messages exist | Empty state |
| | returns only outgoing sending messages older than threshold | Stuck detection |
| | excludes incoming messages | Direction filter |
| | excludes non-sending statuses | Status filter |
| | ordered by timestamp ASC | Sort order |
| | respects limit | Pagination |
| `dbLoadFailedOutgoingGroupMessages` | returns only failed outgoing messages | Failure query |
| | does not return failed incoming messages | Direction filter |
| | ordered by timestamp ASC | Sort order |
| | respects limit | Pagination |
| `dbLoadGroupMessagesWithFailedInboxStore` | returns sent messages with inbox_stored=0 and inbox_retry_payload set | Inbox retry query |
| | excludes messages where inbox_stored=1 | Stored filter |
| | excludes messages with null inbox_retry_payload | Null payload filter |
| | includes pending messages with inbox_stored=0 and retry payload set | Pending inclusion |
| | excludes incoming messages | Direction filter |
| `dbTransitionGroupSendingToFailed` | transitions old sending messages to failed | Transition |
| | does not touch recent sending messages | Threshold guard |
| | does not touch incoming messages | Direction guard |
| | preserves wire_envelope on transitioned rows | Data preservation |
| | returns count of affected rows | Count accuracy |
| `update helpers` | dbUpdateGroupMessageInboxStored sets to 1 | Inbox stored flag |
| | dbUpdateGroupMessageInboxStored sets back to 0 | Flag reset |
| | dbUpdateGroupMessageInboxRetryPayload stores JSON | Retry payload |
| | dbUpdateGroupMessageInboxRetryPayload clears with null | Payload clear |
| | dbUpdateGroupMessageWireEnvelope stores JSON | Wire envelope |
| | dbUpdateGroupMessageWireEnvelope clears with null | Envelope clear |
| | does not affect other rows | Row isolation |
| `GroupMessage model` | fromMap reads wire_envelope | Deserialization |
| | fromMap defaults wire_envelope to null | Default state |
| | fromMap reads inbox_stored as bool | Bool mapping |
| | fromMap reads inbox_retry_payload | Deserialization |
| | toMap serializes inbox_stored as int | Int mapping |
| | copyWith sentinel clears wireEnvelope to null | Sentinel clear |
| | copyWith sentinel clears inboxRetryPayload to null | Sentinel clear |
| | copyWith preserves inboxRetryPayload when not specified | Preserve on copy |
| | copyWith preserves wireEnvelope when not specified | Preserve on copy |

### 2.5 Group Members DB Helpers
**File:** `test/core/database/helpers/group_members_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupMember` | inserts a new member | Insert |
| `dbLoadAllGroupMembers` | returns all members for a group ordered by joined_at ASC | List + sort |
| `dbLoadGroupMember` | returns null for non-existent member | Missing record |
| | returns member when it exists | Lookup |
| | preserves permissions_json | Permission override persistence |
| `dbUpdateGroupMemberRole` | updates the role field | Role update |
| `dbDeleteGroupMember` | deletes a single member | Deletion |
| `dbCountGroupMembers` | returns correct count | Count |
| `dbDeleteAllGroupMembers` | deletes all members for a group | Bulk deletion |

### 2.6 Group Keys DB Helpers
**File:** `test/core/database/helpers/group_keys_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `dbInsertGroupKey` | inserts a new key | Insert |
| `dbLoadLatestGroupKey` | returns null when no keys exist | Empty state |
| | returns the highest generation key | Latest query |
| `dbLoadGroupKeyByGeneration` | returns null for non-existent generation | Missing record |
| | returns the key for the given generation | Lookup |
| `dbLoadAllGroupKeys` | returns all keys ordered by generation ASC | List + sort |
| `dbDeleteAllGroupKeys` | deletes all keys for a group | Bulk deletion |

### 2.7 Group Event Log DB Helpers
**File:** `test/core/database/helpers/group_event_log_db_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `canonicalizeGroupEventLogPayload` | canonical payload ordering is deterministic | Stable canonical JSON for tamper-evident hashing |
| `dbAppendGroupEventLogEntry` | appends entries with per-group hash chain | Sequence, previous hash, and entry hash linkage |
| | exact duplicate source event is idempotent but changed replay is rejected | Replay idempotence and tamper rejection |
| `dbVerifyGroupEventLogChain` | chain verification detects row tampering | Manual DB tamper detection |

### 2.8 Group Invite Delivery Attempts DB Helpers
**File:** `test/core/database/helpers/group_invite_delivery_attempts_db_helpers_test.dart`

| Test | What it covers |
|------|----------------|
| upserts and loads invite delivery attempts by group/member | Group/member lookup and username/status persistence |
| loads all attempts for a group in stable member order | Group-scoped list ordering |
| updates status without losing original attempt timestamp | Status update, updated timestamp, and error clearing |
| deletes rows by group/member and by group | Targeted and group-wide cleanup |

---

## 3. Data Layer (DB Migrations)

### 3.1 Migrations 017/018: original group tables
**File:** `test/core/database/migrations/017_018_group_original_tables_test.dart`

| Test | What it covers |
|------|----------------|
| create baseline group tables, columns, defaults, and indexes | Original `groups`, `group_members`, `group_keys`, and `group_messages` table creation plus baseline indexes and defaults |
| stores and reads baseline member, key, and message rows | Pre-026 group/member/key/message insert and query behavior |
| enforces original constraints and remains idempotent | Type/role/unique/primary-key constraints plus rerunnable migrations 017/018 |

### 3.2 Migration 026: group_messages.quoted_message_id
**File:** `test/core/database/migrations/026_group_quoted_message_id_test.dart`

| Test | What it covers |
|------|----------------|
| adds quoted_message_id column to group_messages | Schema addition |
| existing rows get null quoted_message_id on upgrade | Default value |
| can store a quoted parent id after migration | Write after migration |
| is idempotent | Migration safety |

### 3.3 Migration 048: groups.last_membership_event_at
**File:** `test/core/database/migrations/048_groups_last_membership_event_at_test.dart`

| Test | What it covers |
|------|----------------|
| adds last_membership_event_at column to groups | Schema addition |
| existing rows get null last_membership_event_at on upgrade | Default value |
| can store a membership-event watermark after migration | Write after migration |
| is idempotent | Migration safety |

### 3.4 Migration 049: groups metadata columns
**File:** `test/core/database/migrations/049_groups_metadata_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds avatar and metadata watermark columns to groups | Schema addition |
| existing rows get null metadata columns on upgrade | Default value |
| can store metadata fields after migration | Write after migration |
| is idempotent | Migration safety |

### 3.5 Migration 050: groups.is_muted
**File:** `test/core/database/migrations/050_groups_mute_column_test.dart`

| Test | What it covers |
|------|----------------|
| adds is_muted column to groups | Schema addition |
| existing rows get is_muted = 0 on upgrade | Default value |
| can store muted state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.6 Migration 051: pending_group_invites
**File:** `test/core/database/migrations/051_pending_group_invites_test.dart`

| Test | What it covers |
|------|----------------|
| creates pending_group_invites table | Table creation |
| stores and loads pending invite rows | Read/write |
| is idempotent | Migration safety |

### 3.7 Migration 052: groups dissolve columns
**File:** `test/core/database/migrations/052_groups_dissolve_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds dissolve columns to groups | Schema addition |
| existing rows get non-dissolved defaults on upgrade | Default value |
| can store dissolved state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.8 Migration 053: groups backlog retention columns
**File:** `test/core/database/migrations/053_groups_backlog_retention_columns_test.dart`

| Test | What it covers |
|------|----------------|
| adds backlog retention columns to groups | Schema addition |
| existing rows get null backlog retention defaults on upgrade | Default value |
| can store backlog retention state after migration | Write after migration |
| is idempotent | Migration safety |

### 3.9 Migration 055: group_invite_revocations
**File:** `test/core/database/migrations/055_group_invite_revocations_test.dart`

| Test | What it covers |
|------|----------------|
| creates revocation table and indexes | Table and index creation |
| can store a revoked invite row after migration | Write after migration |
| is idempotent | Migration safety |

### 3.10 Migration 056: group_invite_consumptions
**File:** `test/core/database/migrations/056_group_invite_consumptions_test.dart`

| Test | What it covers |
|------|----------------|
| creates consumption table and indexes | Table and index creation |
| can store a consumed invite row after migration | Write after migration |
| is idempotent | Migration safety |

### 3.11 Migration 057: group_member_permissions
**File:** `test/core/database/migrations/057_group_member_permissions_test.dart`

| Test | What it covers |
|------|----------------|
| adds permissions_json to group_members idempotently | Permission override schema addition and write/read after migration |

### 3.12 Migration 060: group_event_log
**File:** `test/core/database/migrations/060_group_event_log_test.dart`

| Test | What it covers |
|------|----------------|
| creates group event log table and indexes idempotently | Durable `group_event_log` table, uniqueness constraints, indexes, and insertability |

### 3.13 Migration 067: group_invite_delivery_attempts
**File:** `test/core/database/migrations/067_group_invite_delivery_attempts_test.dart`

| Test | What it covers |
|------|----------------|
| creates local invite delivery attempts table and indexes | Local status table columns plus group/status and peer indexes |
| is idempotent | Migration safety |
| enforces one status row per group/member and allowed statuses | `(group_id, peer_id)` uniqueness and status check constraint |

---

## 4. Application Layer

### 4.1 createGroup
**File:** `test/features/groups/application/create_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| creates group successfully | Happy path |
| throws on empty name | Validation |
| throws on bridge error | Error handling |
| saves group, member, and key to repo | Persistence |
| persists creator identity and initial bridge epoch on create | Creator identity and initial key epoch persistence |
| persists the creator username on the admin membership row | Creator identity persistence |
| fails honestly and rolls back when no usable group key is available | Keyless-create rollback |
| creates announcement group with announcement bridge payload and admin metadata | Announcement type |

### 4.2 createGroupWithMembers
**File:** `test/features/groups/application/create_group_with_members_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `createGroupWithMembers` | creates group and returns GroupModel | Happy path |
| | adds all contacts as writer members | Member creation |
| | persists the creator username and exports it in group config | Creator identity propagation |
| | excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out | Partial member-add subset truth |
| | calls callGroupUpdateConfig once with full member list including self | Bridge config sync |
| | broadcasts members_added system message via callGroupPublish | System message |
| | sends individual encrypted P2P invites to each contact | Invite delivery |
| | rolls back staged members when `group:updateConfig` fails after local adds | Config rollback and no invite fan-out |
| | reports mixed or failed invite delivery as an explicit warning result | Invite-degradation truth |
| | reports missing latest key as explicit invite-delivery degradation | Missing-key truth |
| | reports `members_added` publish failure without pretending full invite success | Publish-warning truth |
| | uses auto-generated name from usernames when name is null | Auto-naming |
| | uses auto-generated name with +N suffix for 3+ contacts | Auto-naming overflow |
| | uses provided name when name is not null | Explicit naming |
| | rejects over-limit selection before creating a group | Membership limit |
| | succeeds locally even when P2P invite fails | Partial failure + `needs_resend` invite status |
| | reports missing secure keys as explicit invite degradation | Missing-key truth + `cannot_send` invite status |
| | propagates announcement type into created group, saved group, and updateConfig | Announcement type |

### 4.3 sendGroupMessage
**File:** `test/features/groups/application/send_group_message_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | sends message successfully | Happy path |
| | GM-032 empty active membership disables publish and inbox | Empty private-chat membership fail-closed before publish/inbox |
| | emits GROUP_SEND_MSG_TIMING with group and media metadata | Flow event contract |
| | returns groupNotFound for unknown group | Guard |
| | returns groupDissolved for a dissolved group | Dissolve guard |
| | returns unauthorized for non-admin in announcement group | Announcement guard |
| | rejects stale send after local membership removal before persistence | Removed-sender stale send guard |
| | rejects message when group recovery is in progress | Recovery guard |
| | rejects unauthorized on announcement when recovery pending | Combined guard |
| | allows discussion send while group recovery is in progress | Discussion recovery contract |
| | saves message to repo on success | Persistence |
| | calls group:publish with encrypted wire envelope | Bridge call |
| | builds and encrypts complete wire envelope with timestamps | Envelope construction |
| | stores message in relay inbox on publish | Inbox store |
| | handles messages sent in rapid succession | Rapid-fire |
| | text group message builds preview body like Sender: hello | Push preview |
| | sends quotation as JSON __quote field in plaintext payload | Quoted reply |
| | sends media in plaintext media array within encrypted envelope | Media payload |
| | send succeeds even if inbox store throws | Inbox error isolation |
| | returns error when publish returns ok: false | Publish failure |
| | returns error when publish throws exception | Publish exception |
| | persists explicit inbox success when publish fails | Inbox-only success |
| | publish and inbox store run concurrently | Concurrency |
| | concurrent sending still emits timing event once | Event dedup |
| | inbox store runs even when publish fails | Inbox independence |
| `media attachments` | includes media in publish payload | Media publish |
| | includes media in inbox payload | Media inbox |
| | saves attachments to MediaAttachmentRepository | Media persistence |
| | includes GIF metadata in publish and inbox payloads | GIF metadata |
| | sanitizes text before message ID calculation | Text sanitization |
| | uses provided messageId when given | Explicit ID |
| | DE-003 preserves caller messageId in publish, replay, and retry payloads | Stable caller message id through publish, replay, and retry |
| | uses provided timestamp when given | Explicit timestamp |
| | generates messageId when not provided | Auto ID |
| | message id collision from generator uses a fresh id without overwriting trusted row | Generated collision resolution |
| | message id collision from explicit id resolves without overwriting trusted row | Explicit collision resolution |
| | message id collision guard still allows failed retry in place | Retry reuse |
| | sends message with empty text and media (voice note) | Voice note |
| | rejects message with empty text and no media | Empty guard |
| | rejects message with whitespace-only text and no media | Whitespace guard |
| | sanitizes dangerous bidi controls from text before save | Bidi sanitization |
| | handles message with multiple media attachments | Multi-media |
| | handles message without media (backward compat) | Backward compat |
| | text-only message without media -- no media in payload | No-media path |
| `MS-018: key rotation epoch binding` | send snapshots current epoch for row and replay envelope before publish completes | Send-time epoch snapshot |
| | messages before during and after rotation bind to the locally committed epoch | Before/during/after rotation commit |
| `WU-3: pre-persist and send contract` | pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call | Crash-window durability |
| | pre-persist: unauthorized caller does NOT persist a row | Auth guard |
| | pre-persist: group-not-found does NOT persist a row | Not-found guard |
| `GO-008: log privacy` | EK-002 GI-035 pending inbox retry and flow logs omit protected plaintext | Pending inbox retry and media encryption metadata stay out of flow logs |
| `IR-014: relay replay opacity` | IR-014 group inbox store relay payload omits plaintext and secrets | Relay-visible inbox-store payload stays limited to routing fields plus opaque replay envelope, omits retired push preview fields, and excludes protected plaintext, sender display name, group key, and invite/member secrets |
| `WU-3: 0-peer publish detection and 4-way matrix` | 0-peer + inbox OK -> successNoPeers, status sent | No-peer + inbox OK |
| `GP-007: zero-peer bounded send` | GP-007 zero topic peers complete without retry staging and use inbox | Zero-peer no-visible-delay send + durable inbox custody |
| `DE-006: topicPeers fanout does not imply receipt` | DE-006 topicPeers matrix reports fanout without recipient receipt claim | Zero, partial, and full live fanout diagnostics expose expected recipients, live fanout state, durable inbox state, and no delivered/read receipt claim |
| | DE-006 partial topicPeers with inbox failure stays publish-only and retryable | Partial live fanout plus inbox failure stays pending/retryable, clears publish retry, and creates no delivered/read receipts |
| `DE-007: zero-peer active-recipient durable replay` | DE-007 zero-peer publish stores durable inbox for all active recipients | Zero topic peers return successNoPeers, store encrypted replay for Bob and Charlie, clear retry/wire payloads, preserve sent status, and record no receipt claim |
| `IR-006: active-recipient inbox targeting` | IR-006 group inbox store targets exact active recipients at send time | Removed, declined, expired, never-joined, and sender peer ids are excluded while the active non-sender recipient is targeted |
| `IR-007: inbox-store retry ownership` | IR-007 publish success plus inbox failure is pending and inbox retry closes same id | Publish-success plus failed inbox custody leaves one visible pending row with publish retry cleared and inbox retry retained, then inbox retry stores the same message id exactly once and promotes the row to sent |
| | IR-007 publish failure plus inbox failure is failed and owned by message retry | Publish failure plus failed inbox custody leaves one visible failed row with publish retry retained, excludes it from inbox-only retry, and selects it through failed-message retry ownership |
| `DE-008: publish timeout retry ownership` | DE-008 publish timeout with durable inbox custody is visible sent success (publish timeout + inbox OK surfaces durable success instead of failed) | BRIDGE_TIMEOUT plus durable inbox custody keeps one visible outgoing sent row and clears retry state |
| | DE-008 publish timeout without durable inbox custody leaves one visible failed retryable row | BRIDGE_TIMEOUT plus failed custody leaves one visible failed outgoing row owned by failed-message retry, not inbox-store retry |
| | 0-peer + inbox fail -> error | No-peer + inbox fail + flow event contract |
| | peers > 0 + inbox OK -> success, both payloads cleared | Peers + inbox OK |
| | peers > 0 + inbox fail -> success, status pending with retry payload | Peers + inbox fail |
| | topicPeers null + inbox OK -> legacy success stays sent | Legacy + inbox OK |
| | topicPeers null + inbox fail -> legacy error | Legacy + inbox fail |
| | missing topicPeers + inbox OK -> legacy success stays sent | Missing peers + inbox OK |
| | missing topicPeers + inbox fail -> error | Missing peers + inbox fail |
| | inbox store ok:false is treated as inbox failure | Inbox ok:false |
| | missing topicPeers (old bridge) + success -> legacy behavior | Legacy bridge compat |

### 4.4 sendGroupInvite
**File:** `test/features/groups/application/send_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `sendGroupInvite` | encrypts invite payload with recipient binding and sends to recipient via p2pService | Happy path |
| | returns encryptionRequired when recipientMlKemPublicKey is null | Key guard |
| | returns nodeNotRunning when p2pService is not started | Node guard |
| | returns sendFailed when bridge encrypt returns ok=false | Encrypt failure |
| | returns sendFailed when p2pService returns false and inbox fails | Send + inbox failure |
| | stores invite in inbox when direct send fails | Inbox fallback + `queued` result |
| | invite payload includes full groupConfig with members array | Payload shape |
| | keeps join material and policy details inside encrypted invite payload | Direct + inbox invite privacy |
| `sendGroupInvitesInParallel` | sends invites to all recipients and returns per-recipient outcomes | Batch send |
| | runs invites concurrently | Concurrency |
| | counts only successful invites when some fail | Partial failure |
| | returns 0 for empty recipients list | Empty input |
| | continues sending when one invite throws | Error isolation |

### 4.5 handleIncomingGroupMessage
**File:** `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | handles incoming message successfully | Happy path |
| | records incoming message in tamper-evident event log | DB-002 event-log append coverage |
| | event log rejects tampered duplicate before stored message changes | DB-002 event-log replay/tamper guard |
| | persists same-self delivery as local sent history | Multi-device |
| | DE-005 self echo reconciles pending outbound row without creating incoming duplicate | Sender self-echo promotes the existing pending local row to sent without creating an incoming duplicate |
| | DE-005 self echo ignores mismatched transport identity without promoting outbound row | Sender self-echo reconciliation rejects mismatched transport identity and leaves the pending row unchanged |
| | strips dangerous bidi controls and preserves safe markers on incoming save | Bidi sanitization |
| | ignores message for unknown group | Unknown group guard |
| | saves message to repo | Persistence |
| | duplicate by messageId skips repeated group and member lookups | Dedup optimization |
| | persists quotedMessageId from incoming payload | Quoted reply |
| | still processes messages from unknown members | Unknown member tolerance |
| | accepts removed-sender message when it predates the persisted removal cutoff | Pre-cutoff tolerance |
| | rejects removed-sender message when it is at the persisted removal cutoff | At-cutoff rejection |
| | still processes unknown sender when persisted removal cutoff belongs to another peer | Peer-scoped cutoff |
| | accepts a message that predates the persisted dissolve cutoff | Pre-dissolve tolerance |
| | rejects a message at or after the persisted dissolve cutoff | Post-dissolve rejection |
| | deduplicates identical incoming messages | Content dedup |
| | deduplicates messages after sanitizing invisible bidi controls | Sanitized dedup |
| | allows messages with different text or timestamp | False-positive guard |
| | far future incoming timestamp is clamped to receive time | Future-skew clamp |
| | past current and near future timestamps retain chronological order | Clock-skew ordering |
| | deduplicates by messageId when pubsub and group inbox deliver same message | Cross-path dedup |
| | duplicate replay enriches a missing quotedMessageId | Quote enrichment |
| | duplicate replay with the same messageId ignores a tampered timestamp | Replay tamper dedup |
| | duplicate replay with the same messageId ignores conflicting content | Replay content tamper dedup |
| | duplicate group inbox replay does not resave media | Media dedup |
| | replayed removed-sender message after cutoff does not overwrite the accepted pre-cutoff row | Replay + removal cutoff |
| | replayed message after dissolve cutoff does not overwrite the accepted pre-dissolve row | Replay + dissolve cutoff |
| `media attachments` | saves media attachments when media list provided | Media persistence |
| | creates MediaAttachment with downloadStatus pending | Download status |
| | handles message without media (backward compat) | Backward compat |
| | ignores duplicate messages -- does not re-save media | Dedup + media |

### 4.6 addGroupMember
**File:** `test/features/groups/application/add_group_member_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| adds member successfully when caller is admin | Happy path |
| allows adding the 50th member under the shared contract | Limit boundary |
| rejects when caller is not admin | Auth guard and no local/bridge side effects |
| allows writer with invite permission override to add a member | Permission override grant |
| denies admin whose invite permission override is false | Permission override deny |
| rechecks revoked invite permission before adding a queued member | Stale permission recheck |
| rejects while group recovery is in progress | Recovery guard |
| throws when group not found | Not-found guard |
| rejects duplicate member before sync and preserves original row | Duplicate guard |
| rejects adding a 51st member before config sync | Over-limit guard |
| saves member to repo | Persistence |
| rolls back DB when group:updateConfig fails | Rollback |
| syncBridgeConfig false skips bridge config sync | Skip-sync path |
| GM-002 addGroupMember syncs updated A/B/C/D config payload | Host/config proof for Add D while A/B/C are online; non-closing without exact device E2E |

### 4.7 removeGroupMember
**File:** `test/features/groups/application/remove_group_member_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| removes member from DB | Deletion |
| calls group:updateConfig to update Go validator | Bridge sync |
| does NOT call group:rotateKey | No legacy rotate |
| throws when caller is not admin | Auth guard |
| allows writer with remove permission override to remove member | Permission override grant |
| denies admin whose remove permission override is false | Permission override deny |
| rechecks revoked remove permission before removing a queued target | Stale permission recheck |
| blocks removing the last admin before local or bridge changes | Last-admin guard |
| allows removing an admin when another admin remains | Multi-admin removal |
| rejects while group recovery is in progress | Recovery guard |
| rejects non-member before sync and preserves existing members | Non-member guard |
| removes member from DB before calling bridge | Order of operations |
| groupConfig sent to bridge excludes removed member | Config correctness |
| groupConfig has correct structure with all required fields | Config shape |
| restores removed member when group:updateConfig fails | Rollback |

### 4.8 updateGroupMemberRole
**File:** `test/features/groups/application/update_group_member_role_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| promotes member to admin and syncs bridge config | Happy path |
| rejects non-admin caller | Auth guard |
| allows writer with manage-roles permission override to update role | Permission override grant |
| writer with manage-roles permission cannot promote a member to admin | Permission escalation guard |
| denies admin whose manage-roles permission override is false | Permission override deny |
| rechecks revoked manage-roles permission before applying queued role update | Stale permission recheck |
| rejects non-member target before sync | Non-member guard |
| blocks removing the last admin from the group | Last-admin guard |
| allows self demotion when another admin remains and updates myRole | Self-demotion |
| rejects while group recovery is in progress | Recovery guard |

### 4.9 archiveGroup / unarchiveGroup
**File:** `test/features/groups/application/archive_group_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `archiveGroup` | calls groupRepo.archiveGroup(groupId) successfully | Happy path |
| | propagates errors from repository | Error propagation |

**File:** `test/features/groups/application/unarchive_group_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `unarchiveGroup` | calls groupRepo.unarchiveGroup(groupId) successfully | Happy path |
| | propagates errors from repository | Error propagation |

### 4.10 joinGroup
**File:** `test/features/groups/application/join_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| joins group successfully | Happy path |
| saves group, member, and key | Persistence |
| calls bridge join command | Bridge call |

### 4.11 leaveGroup
**File:** `test/features/groups/application/leave_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| leaves group successfully | Happy path |
| cleans up all data (members, keys, group) | Cleanup |
| calls bridge leave command | Bridge call |
| blocks sole admin from leaving | Sole-admin guard |
| allows admin to leave when another admin exists | Multi-admin leave |

### 4.12 deleteGroupAndMessages
**File:** `test/features/groups/application/delete_group_and_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `deleteGroupAndMessages` | deletes group messages first, then calls leaveGroup | Order of operations |
| | dissolved local cleanup deletes group state without publishing group leave | Device-local dissolved cleanup |
| | propagates errors from message deletion | Error propagation |

### 4.13 dissolveGroup
**File:** `test/features/groups/application/dissolve_group_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| dissolves a group, stores a timeline event, and leaves the topic | Happy path + durable closure fields |
| GM-032 dissolved group disables publish and inbox while preserving history | Dissolved private chat blocks later publish/inbox and keeps historical rows |
| returns unauthorized for non-admin users | Auth guard |
| returns alreadyDissolved when the group is already closed | Idempotency guard preserving closure fields |
| repeated dissolve preserves closure state and does not publish again | Repeated dissolve idempotency + duplicate publish guard |
| returns bridgeError when inbox fallback fails but still marks the group dissolved | Partial failure |

### 4.14 updateGroupMetadata
**File:** `test/features/groups/application/update_group_metadata_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `updateGroupMetadata` | updates name, description, avatar metadata, and watermark | Happy path |
| | builds stable version and canonical state hash for settings | Settings version + canonical hash |
| | clears blank description and avatar fields explicitly | Blank field clearing |
| | rejects non-admin edits | Auth guard |
| | rechecks demoted local role before applying queued metadata edit | Stale role recheck |
| | rejects empty names | Validation |

### 4.15 setGroupMuted
**File:** `test/features/groups/application/set_group_muted_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `setGroupMuted` | updates mute state for an existing group | Happy path |
| | throws when the group does not exist | Not-found guard |

### 4.16 rotateGroupKey
**File:** `test/features/groups/application/rotate_group_key_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| rotates key successfully | Happy path |
| saves new key to repo | Persistence |
| returns GroupKeyInfo with correct data | Return value |

### 4.17 rotateAndDistributeGroupKey
**File:** `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| allows writer with rotate permission override to rotate keys | Permission override grant |
| denies admin whose rotate permission override is false | Permission override deny |
| rechecks revoked rotate permission before generating a queued key | Stale permission recheck |
| promotes generated key only after distribution completes | Ordering |
| KE-021 removed member is excluded from future direct key update fanout | After removal, future rotation direct key-update fanout targets only remaining Bob device identities, excludes removed C peer/device/transport IDs, and leaves removed C with only epoch-1 local key material |
| distribution completes before admin update and broadcast | Ordering |
| calls bridge to encrypt key for each non-self member | Per-member encrypt |
| broadcasts key_rotated system message | System message |
| sends key update to each non-self member via p2p | Key distribution |
| returns null when generate-next-key fails (ok: false) | Keygen failure |
| skips members without mlKemPublicKey | Missing key skip |
| continues distribution when per-member encrypt fails | Error isolation |
| continues distribution when sendP2PMessage throws | Error isolation |
| distribution timeout does not block later recipients | Timeout isolation |
| updates admin key after distribution timeout | Timeout recovery |

### 4.18 handleIncomingGroupInvite
**File:** `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleIncomingGroupInvite` | persists group, members, and key for a valid invite payload | Happy path |
| | persists avatar metadata and downloaded path when invite carries it | Avatar persistence |
| | calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch | Bridge call |
| | returns duplicateGroup when group already exists | Duplicate guard |
| | returns invalidPayload for missing groupId | Missing field guard |
| | returns invalidPayload for missing groupKey | Missing field guard |
| | returns invalidPayload for empty groupKey before state or join | Missing join material guard |
| | returns invalidPayload for missing groupConfig | Missing field guard |
| | returns unknownSender for invite from non-contact | Unknown sender guard |
| | joining user gets myRole=member in the persisted GroupModel | Role assignment |
| | returns bridgeError when group:join times out | Timeout handling |
| | decrypts v2 invite envelope and processes inner payload | v2 decryption |
| | returns decryptionFailed when bridge decrypt returns ok=false | Decrypt failure |
| | returns decryptionFailed when mlKemSecretKey is null and envelope is v2 | Missing key guard |
| | persists correct myRole as member (not admin) | Role validation |
| | persists all members from groupConfig, not just sender | Multi-member persistence |
| | rejects v1 invite where transport sender != payload sender | Sender mismatch guard |
| | rejects v2 encrypted invite where transport sender != payload sender | v2 sender mismatch guard |
| | accepts bound invite when recipient peer matches local identity | Recipient binding happy path |
| | rejects v1 invite bound to a different recipient peer | Wrong recipient guard |
| | rejects v2 encrypted invite bound to a different recipient peer | v2 wrong recipient guard |
| | handles bridge group:join timeout without losing persisted data | Timeout data safety |

### 4.19 storePendingGroupInvite
**File:** `test/features/groups/application/store_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `storeIncomingPendingGroupInvite` | stores validated invite as pending without creating group state | Happy path |
| | ignores delayed invite copy when invite was revoked | Revocation replay guard |
| | ignores delayed invite copy when invite was already used | Consumption replay guard |
| | returns duplicateGroup when group already exists | Duplicate guard |
| | returns unknownSender when contact is missing | Unknown sender guard |

### 4.20 acceptPendingGroupInvite
**File:** `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `acceptPendingGroupInvite` | accepts pending invite, persists group, and drains inbox | Happy path |
| | accept replays backlog reactions when reactionRepo is provided | Invite-accept immediate reaction catch-up |
| | successful accept publishes a durable join event for the group | Durable join history |
| | bridgeError keeps the persisted group and clears the pending invite row | Accepted-but-degraded persistence |
| | missing join material stays pending for repair without creating group state | Missing join material repair state |
| | returns expired and removes stale invite | Expiry guard |
| | returns revoked and removes stale pending row without joining | Revoked-accept guard |
| | returns alreadyUsed and removes stale pending row without joining | Consumption replay guard |
| | returns duplicateGroup and removes pending row when group already exists | Duplicate guard |
| | accepting on one device does not clear the sibling device pending invite | Multi-device |

### 4.20a revokePendingGroupInvite
**File:** `test/features/groups/application/revoke_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `revokePendingGroupInvite` | removes pending row and records a revocation tombstone | Revocation happy path |
| | returns notFound without writing a tombstone | Missing invite guard |

### 4.21 declinePendingGroupInvite
**File:** `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `declinePendingGroupInvite` | deletes pending invite on decline | Happy path |
| | returns expired when declining an expired invite | Expiry guard |
| | declining on one device does not clear the sibling device pending invite | Multi-device |

### 4.22 drainGroupOfflineInbox
**File:** `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | resume drains group inbox for every joined group | Happy path |
| | drain after watchdog restart retrieves messages exactly once | Idempotency |
| | drain after in-place recovery still allowed and idempotent | Recovery compat |
| | drains groups concurrently so one slow inbox does not serially stall others | Concurrency |
| | replayed member_removed routes through listener cleanup instead of saving a chat row | System message routing |
| | replayed reaction routes through reactionRepo when present | Reaction routing |
| | handles bad inbox data gracefully | Error handling |
| | skips backward compat v1 member_added messages without peerId | Legacy compat |
| | repeated drains do not resurrect expired backlog | Retention enforcement |
| | backlog expires after stale window | Stale backlog |
| | drain preserves quotedMessageId from inbox payload | Quoted reply |
| | DE-004 listener-backed live plus replay dedupes while preserving replay receipts and metadata | Listener-backed duplicate replay keeps one visible row, preserves first live fields, enriches quote/media metadata, commits replay read/local-delivered receipt evidence, marks read, and advances cursor |
| | filters out messages with null group | Null group guard |
| | deduplicates messages by messageId | Dedup |
| | saves correct status based on direction | Status mapping |
| | persists wire envelope and inbox retry payload | Payload persistence |
| | emits GROUP_DRAIN_OFFLINE_INBOX_TIMING with batch metadata | Batch flow event contract |
| | drains offline inbox and saves messages to repo | Persistence |
| | handles multiple pages with cursor pagination | Pagination |
| | IR-002 cursor drain resumes after restart and delivers every page exactly once | First-page-only drain persists cursor, restart resumes from durable cursor, remaining pages drain exactly once, and redrain stays idempotent |
| | IR-003 timestamp high-water replay includes boundary messages and dedupes ids | Timestamp fallback stores inclusive high-water cursor, replays same-boundary messages, and dedupes repeated ids |
| | IR-004 removed offline member rejects post-removal replay before decrypt | Recipient-excluded post-removal replay skips before payload verify/decrypt, stores no plaintext or placeholder, creates no repair exposure, and emits recipient-skip flow evidence |
| | IR-005 KE-018 drains only replay windows addressed to re-added member | Re-added Charlie retains entitled pre-removal replay, skips removed-window replay, receives post-readd replay, and only issues distinct decrypt attempts for the two entitled envelopes |
| | IR-008 retrieve failure leaves cursor and ack state unchanged until retry | Failed cursor retrieve leaves the durable cursor, message rows, and delivered/read receipts unchanged, then retry requests the same cursor and persists the page exactly once |
| | IR-009 persistence failure retries same page before cursor or ack commit | Local save failure during replay leaves no message row, cursor, delivered/read receipt, or read-state ack, then retry requests the same cursor and persists the message once before committing ack/cursor state |
| | IR-010 drains valid cursor historyGaps into repair lifecycle and ignores invalid gaps | Valid cursor history gaps create persisted repair lifecycle rows with expected cursor/source identity, while invalid gap entries create no repairs or messages |
| | IR-011 history repair request validates gap identity and source peer before mutation | Wrong-group gaps are skipped, unauthorized/self sources are not requested, wrong group/gap/source repair responses insert no messages, and only the valid fallback repairs the gap |
| | IR-012 history repair rejects wrong hash and head before fallback insert | Bad-hash and wrong-head repair responses insert no supplied messages, a later valid source repairs the gap, and only the valid repaired message id is recorded |
| | IR-013 unauthorized repair source cannot inject before fallback | Unauthorized repair candidates are recorded but receive no repair request, forged returned-source responses are rejected, and only the authorized fallback repaired message is inserted |
| | IR-015 replay rehydrates text quote image video file GIF and voice after live duplicate | Live-plus-replay duplicate persists one row while preserving quote target, key epoch, and image/video/file/GIF/voice media descriptors including duration and waveform |
| | IR-016 long offline cutoff keeps retained backlog and records incomplete history | Multi-page expired-plus-retained replay skips expired plaintext, persists only retained backlog, records explicit expired/retained cutoff timestamps, and advances the durable cursor |
| | IR-019 decrypts hidden payload message id for inbox dedupe | Relay response and signed replay envelope omit outer message id, drain decrypts the payload message id, dedupes against the trusted live row, preserves local content/timestamp, commits delivered evidence, and advances the cursor |
| | does not crash on empty inbox | Empty state |
| | handles cursor null on empty inbox | Null cursor |
| | drains inbox for archived groups too | Archived inclusion |
| | drains inbox message with media -- saves media attachments | Media drain |
| | GMAR-004 duplicate live plus inbox replay enriches video and voice media once | Signed replay duplicate/enrichment proof: sparse live media is enriched once with video/voice metadata and one attachment set |
| | drains mixed epoch encrypted replay out of order without rewriting epochs | MS-018 mixed-epoch replay |
| | future epoch encrypted replay creates one undecryptable placeholder without decrypting | MS-018/OS-009 future-epoch placeholder |
| | GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival | Live diagnostic plus durable replay/key-arrival repair convergence |
| | GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival | Partial rotation/send race: stale recipient pending state, durable replay canonical identity, later key-arrival repair, and exactly-once dedupe |
| | KE-021 future group inbox replay excludes removed member and stale key cannot decrypt | Post-removal `group:inboxStore` and persisted retry recipients exclude removed C, replay uses future epoch 2, missing future key saves only an undecryptable placeholder, and key-bound stale material does not reveal plaintext |
| | MD-011 removed member cannot decode future media replay with only the old epoch | Removed peer with only epoch 1 skips epoch-2 future media before message, media, download, or decrypt persistence |
| | GO-008 cursor error flow logs redact JSON payload plaintext and keys | Cursor-error diagnostics redact embedded plaintext/key fragments |
| | GI-034 offline replay suppresses duplicate notifications and preserves unread state | Offline replay through the real listener consumes a recent remote-push marker, dedupes duplicate replay notifications, emits one local notification for the distinct replay, and preserves read/unread state across duplicate re-drain |
| | drains group_reaction items when reactionRepo is provided | Reaction drain |
| `drainGroupOfflineInbox use case` | resume drains all groups concurrently | Batch drain |
| | watchdog restart drains missed group messages exactly once | Watchdog idempotency |
| | in-place recovery allows resync while draining | Recovery sync |

### 4.22a groupOfflineReplayEnvelope
**File:** `test/features/groups/application/group_offline_replay_envelope_test.dart`

| Test | What it covers |
|------|----------------|
| GK-028 decode rejects senderPublicKey tamper before decrypt | Durable replay uses configured sender key verification and rejects legacy sender-key tamper before decrypt |

### 4.23 recoverStuckSendingGroupMessages
**File:** `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `recoverStuckSendingGroupMessages` | returns count from repo and transitions stuck rows to failed | Happy path |
| | returns 0 when nothing is stuck | Empty state |
| | respects the supplied threshold | Threshold param |

### 4.24 retryFailedGroupInboxStores
**File:** `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| retries eligible sent messages and clears inbox retry state | Happy path + begin/ok/done/timing flow events |
| retries eligible pending messages and promotes them to sent | Pending promotion |
| IR-007 inbox retry sends same pending message id once without duplicate rows | Inbox retry sends the persisted pending row message id, clears retry state, leaves one visible row, and a second pass neither duplicates nor resends |
| skips messages that are already inbox_stored | Skip guard |
| handles callGroupInboxStore failure gracefully | Error handling + per-message flow event |
| respects batch limit | Batch size |
| returns 0 when no eligible messages | Empty state |
| skips legacy rows with null inbox_retry_payload | Legacy compat |

### 4.25 retryFailedGroupMessages
**File:** `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `retryFailedGroupMessages` | returns 0 when identity is null | Null identity guard |
| | emits RETRY_FAILED_GROUP_MESSAGES_TIMING with total and skipped counts | Start/found/success/complete/timing flow events |
| | retries a text-only failed row in place using the original ids | Text retry |
| | retries a zero-peer plus inbox-fail row through the failed-message retry owner | Zero-peer retry owner |
| | DE-008 retry of timeout-owned failed row reuses message id and clears invisible failed state | Timeout-owned failed row retry preserves original messageId, clears failed/retry state, and leaves one sent row |
| | retries a failed text row even when inboxRetryPayload was cleared after inbox success | Cleared payload retry |
| | retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success | Media retry |
| | retries a failed GIF row from persisted done attachments with image/gif preserved | GIF retry |
| | skips rows whose persisted media attachments are still upload_pending | Upload-pending skip + skipped-reason flow event |
| | skips media retry rows when no resendable persisted attachments exist | No-attachment skip |
| | continues after a per-message publish error | Error isolation |
| | does not replay a failed text row after sender was removed locally | Removed-sender retry guard |
| | retryFailedGroupMessage only retries the requested failed media row | Targeted retry |

### 4.26 retryIncompleteGroupUploads
**File:** `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `retryIncompleteGroupUploads` | returns 0 when no upload_pending attachments exist | Empty state |
| | reuploads only group upload_pending attachments and uses blobId | Upload retry + recipient-only upload ACL |
| | reuploads only pending GIF attachments while preserving done JPEG siblings | GIF retry |
| | emits RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING with attachment and message counts | Flow event |
| | transient failure increments retry count and terminal state at max | Retry exhaustion |
| | skips retry work when upload_pending attachments have no parent group message row | Orphan skip |
| | skips the final group send when the parent row is deleted after uploads complete | Deleted parent skip |
| | MD-011 retry excludes a removed member from media ACLs and inbox recipients | Post-removal retry upload `allowedPeers` and group inbox recipients exclude removed C |

### 4.27 GroupMessageListener
**File:** `test/features/groups/application/group_message_listener_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | processes valid message | Happy path |
| | forwards quotedMessageId from event into persisted message | Quoted reply forwarding |
| | caches self peer id across multiple handled messages | Self-ID cache |
| | DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates | Dispatcher overflow diagnostics trigger one replay recovery for group-message drops, coalesce duplicate diagnostics, ignore non-message overflow, and do not persist placeholder rows |
| | IR-017 dispatcher overflow diagnostic names replay recovery reason | Dispatcher overflow recovery preserves message-event overflow state, dropped count, queue depth, max queue size, and recovery reason details in requested/done flow events |
| | DE-013 malformed group message schema rejects before persistence and valid later event persists | Listener-entry schema guard rejects malformed group message events with safe diagnostics before persistence and allows a later valid event |
| | DE-014 decryption failure queues repair placeholder and later valid event still persists | Live decryption-failure diagnostic creates one safe pending-key repair placeholder and repair request, redacts secret diagnostic text from flow evidence, and allows later valid live delivery |
| | DE-017 content before member add is buffered then respects joined interval | Live content delivered before the matching member add waits for membership and flushes only inside the joined interval |
| | DE-017 member removal repairs post-removal content while preserving prior content | Removal watermark removes or buffers post-removal content without deleting entitled pre-removal history |
| | ignores message for unknown group | Unknown group guard |
| | emits to stream on valid message | Stream emission |
| | disposes correctly | Cleanup |
| | handles malformed data without crashing | Error resilience |
| `system messages` | member_added saves member and calls updateConfig | Member-add system msg |
| | member_added emits readable timeline event on groupMessageStream | Durable add timeline |
| | unauthorized member_added is ignored | Auth guard |
| | group_metadata_updated refreshes group metadata and stores a timeline event | Metadata update |
| | tampered group_metadata_updated state hash is ignored without mutating group state | Metadata hash tamper guard |
| | unauthorized group_metadata_updated is ignored | Auth guard |
| | members_added saves all members and calls updateConfig | Batch member-add |
| | member_joined saves a durable join timeline event | Durable join timeline |
| | member_joined marks invite delivery status as joined | Invite status convergence |
| | unauthorized members_added is ignored | Auth guard |
| `member_removed system messages` | unauthorized member_removed is ignored | Auth guard |
| | replayed unauthorized member_removed is ignored | Replay auth guard |
| | GM-032 all-members-removed snapshot dissolves, leaves, and preserves history | Authoritative empty-members snapshot terminal closure |
| | handles key_rotated system message without error | Key rotation |
| | removal of other member does NOT call leaveGroup | Non-self removal |
| | member_role_updated changes role and calls updateConfig | Role update |
| | member_role_updated logs event and rejects tampered replay before mutation | DB-002 system event-log replay/tamper guard |
| | unauthorized member_role_updated is ignored | Auth guard |
| | limited manager member_role_updated cannot promote a member to admin | Permission escalation guard |
| | limited manager member_role_updated cannot grant unheld permissions | Permission escalation guard |
| `media forwarding` | handles event without media field (backward compat) | Backward compat |
| `group notifications` | shows notification for incoming group message | Notification display |
| | suppresses notification when viewing group conversation | Active view suppression |
| | does not notify for own messages | Self-message suppression |
| | DE-005 self echo emits reconciled outbound row once | Sender self-echo listener path emits the reconciled outgoing row exactly once without notification duplication |
| | does not notify after self-removal deletes the group | Post-removal suppression |
| | does not notify when notification deps are null | Null deps guard |
| | shows notification when viewing different group | Cross-group notification |
| `group reactions` | emits removal ReactionChange when action is remove | Reaction removal |
| | ignores reaction when reactionRepo is null | Null repo guard |
| | ignores malformed reaction data | Malformed data guard |
| `group_dissolved system messages` | replayed group_dissolved is idempotent | Dissolve replay |
| | unauthorized group_dissolved is ignored | Auth guard |
| `system messages` | unauthorized mutation system events leave local state and bridge unchanged | Receive-side authorization matrix |

### 4.28 GroupInviteListener
**File:** `test/features/groups/application/group_invite_listener_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInviteListener` | stores a valid v2 invite as pending and does not join immediately | Happy path |
| | does not store pending invite from unknown sender | Unknown sender guard |
| | does not store pending invite for an already joined group | Duplicate guard |
| | does not crash on decryption failure | Decryption error |
| | calling start twice does not create duplicate subscriptions | Double-start guard |
| | stop prevents further processing | Stop lifecycle |
| | dispose is safe after start | Dispose lifecycle |
| | does not process invite from blocked contact | Block guard |
| | duplicate pending invite replaces the existing preview row | Upsert |

### 4.29 GroupKeyUpdateListener
**File:** `test/features/groups/application/group_key_update_listener_test.dart`

| Test | What it covers |
|------|----------------|
| logs key update and rejects tampered replay before replacing key | DB-002 key-update event-log replay/tamper guard |
| saves key on successful decrypt | Happy path |
| promotes key only after group:updateKey succeeds | Ordering |
| returns early when encrypted field is null | Null guard |
| returns early when own ML-KEM secret key is null | Missing key guard |
| returns early when decrypt fails (ok: false) | Decrypt failure |
| saves key to DB AND updates Go via group:updateKey | Dual persistence |
| does not crash on malformed JSON | Error resilience |
| group:updateKey payload contains correct groupId, groupKey, keyEpoch | Payload shape |
| send during pending key update uses old epoch until local update commits | MS-018 pending update send |
| handles sequential key updates (epoch 2 then epoch 3) | Higher-epoch convergence |
| delayed older key update after newer generation does not promote active key | GEK-001 stale older direct update guard |
| conflicting same-generation key updates keep first accepted material | GEK-001 same-epoch conflict guard |
| duplicate same-generation key update with same material is idempotent | GEK-001 duplicate same-epoch idempotency |
| conflicting delayed older key update does not replace historical material | GEK-001 historical material conflict guard |
| KE-022 group:updateKey bridge failure keeps the old key active, reports diagnostics, and requests recovery | Bridge failure guard + repair request diagnostics |

### 4.30 Reactions (send / handle / remove)
**File:** `test/features/groups/application/send_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| chat member can react | Happy path |
| announcement member can react | Announcement react |
| dissolved chat group rejects reactions without publishing or storing | Dissolved send guard |
| dissolved announcement member cannot add a reaction | Dissolved announcement guard |
| non-member is rejected | Auth guard |
| unknown messageId is rejected | Missing message guard |
| unknown group is rejected | Missing group guard |
| publish failure returns publishFailed | Publish failure |

**File:** `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| upserts reaction | Happy path |
| replaces prior emoji from same sender | Upsert replace |
| removes reaction on remove action | Remove action |
| returns unknownGroup for nonexistent group | Missing group guard |
| returns parseError for invalid JSON | Parse error |
| still processes reaction from unknown sender (stale member list) | Stale member tolerance |
| rejects add when payload sender mismatches outer sender | Sender auth guard |
| rejects remove when payload sender mismatches outer sender | Sender auth guard |
| ignores add reactions at or after the dissolve cutoff | Dissolve cutoff guard |
| ignores remove reactions at or after the dissolve cutoff | Dissolve cutoff guard |
| accepts late replayed reactions when the payload predates dissolve | Pre-dissolve replay tolerance |

**File:** `test/features/groups/application/remove_group_reaction_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| removes own reaction | Happy path |
| is idempotent when reaction absent | Idempotency |
| non-member is rejected | Auth guard |
| dissolved group rejects remove and preserves the stored reaction | Dissolved remove guard |

### 4.31 rejoinGroupTopics
**File:** `test/features/groups/application/rejoin_group_topics_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `rejoinGroupTopics` | calls callGroupJoinWithConfig for each active group | Happy path |
| | emits GROUP_REJOIN_TOPICS_TIMING with batch metadata | Begin/joined/done/timing flow events |
| | skips groups with no key info | Missing key skip |
| | continues on individual join error | Error isolation |
| | does nothing when no active groups exist | Empty state |
| | builds correct groupConfig from stored members | Config construction |
| | rejoin is idempotent when topic already active | Idempotency |
| | rejoin runs after watchdog restart | Watchdog trigger |
| | node-requested recovery rejoins topics | Recovery trigger |
| | in-place recovery refreshes topics idempotently | In-place recovery |
| | announcement groups are rejoined and refreshed like normal groups | Announcement rejoin |
| | watchdog restart triggers group rejoin for all groups | Watchdog batch |
| | in place relay recovery still refreshes group topics | Relay recovery |
| | startup triggers group rejoin for all groups | Startup trigger |
| | groups without key material are skipped | Key guard |
| | error in one group does not prevent other groups from being rejoined | Error isolation + per-group error flow events |
| | rejoins archived groups | Archived inclusion |
| | skips dissolved groups | Dissolved exclusion + rejoin result counts |

### 4.32 groupAvatarStorage
**File:** `test/features/groups/application/group_avatar_storage_test.dart`

| Test | What it covers |
|------|----------------|
| downloadGroupAvatar creates the group avatar directory before bridge download | Directory creation |

### 4.33 Member Removal Integration
**File:** `test/features/groups/application/member_removal_integration_test.dart`

| Test | What it covers |
|------|----------------|
| complete admin removal flow produces correct bridge command sequence | Command order including persisted epoch restore before generate and promotion update after distribution |
| rotated key is NOT distributed to removed member | Removed member future-key exclusion |
| receiver processes key update and syncs Go validator | Key update receipt |
| first post-removal send uses the rotated epoch | Epoch advancement |
| voluntary leave rotation excludes leaver and remaining members send on rotated epoch | Voluntary leave rotation baseline |

### 4.34 resendGroupInvite
**File:** `test/features/groups/application/resend_group_invite_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| resend sends only the invite and updates status to sent | Manual resend happy path, no `group:publish`, no duplicate member |
| resend records needs_resend when direct and inbox delivery fail | Failed resend status persistence and inbox fallback attempt |
| resend does not add missing members | Missing-member guard and no send side effects |

---

## 5. Presentation Layer

### 5.1 GroupListScreen
**File:** `test/features/groups/presentation/group_list_screen_test.dart`

| Test | What it covers |
|------|----------------|
| renders groups | Rendering |
| shows empty state when no groups | Empty state |
| shows loading placeholders while groups are loading | Loading state |
| shows group list when groups are available even if isLoading is still true | Loading + data |
| shows type badges | Badge rendering |
| renders pending invite review card and actions | Invite card |
| renders expired pending invite as non-joinable | Expired invite |
| does not show FAB (FAB moved to Orbit screen) | FAB removal |
| IR-016 shows expired backlog summary on the group card | Backlog summary |
| IR-016 shows mixed-window backlog summary alongside latest message | Retention summary |

### 5.2 GroupListScreen BiDi
**File:** `test/features/groups/presentation/group_list_screen_bidi_test.dart`

| Test | What it covers |
|------|----------------|
| does not flatten sender and body into a single preview string | BiDi preview |

### 5.3 GroupListWired
**File:** `test/features/groups/presentation/group_list_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupListWired` | loads and displays active groups on init | Init loading |
| | reloads renamed group metadata after a message refresh | Metadata reload |
| | shows loading placeholders before groups resolve | Loading state |
| | refreshes group list when groupMessageListener emits | Message stream |
| | refreshes group list when groupInviteListener emits | Invite stream |
| | loads pending invites on init | Invite loading |
| | refreshes pending invite list when pending invite stream emits | Invite stream |
| | accepting a pending invite joins the group and removes the row | Accept flow + immediate replay catch-up |
| | bridgeError accept keeps the joined group and shows recovery warning | Honest degraded state |
| | repair-pending accept keeps the invite row and shows key-material warning | Pending repair state |
| | declining a pending invite removes the row without joining | Decline flow |
| | tapping group navigates to conversation | Navigation |
| | shows unread counts | Unread badge |
| | loading skeleton replaced by empty state when no groups | Empty transition |
| | loading clears on error | Error recovery |

### 5.4 GroupCard
**File:** `test/features/groups/presentation/group_card_test.dart`

| Test | What it covers |
|------|----------------|
| renders group name and type badge | Rendering |
| shows unread count when > 0 | Unread badge |

### 5.5 GroupCard BiDi
**File:** `test/features/groups/presentation/group_card_bidi_test.dart`

| Test | What it covers |
|------|----------------|
| announcement preview separates sender label from Arabic-first mixed body | BiDi preview |
| group preview keeps English-first body LTR even with mixed sender name | LTR text |
| dissolved groups show a badge and fallback preview | Dissolved state |

### 5.6 GroupTypeBadge
**File:** `test/features/groups/presentation/group_type_badge_test.dart`

| Test | What it covers |
|------|----------------|
| renders correct text for each type | Badge text |
| each type has unique color | Badge color |

### 5.7 GroupConversationScreen
**File:** `test/features/groups/presentation/group_conversation_screen_test.dart`

| Test | What it covers |
|------|----------------|
| renders messages | Message rendering |
| renders sender identity with UserAvatar in conversation rows | Avatar consistency |
| keeps non-photo fallback identity readable in conversation rows | Readable avatar fallback |
| shows compose area when canWrite is true | Compose visibility |
| long-press opens one coherent context surface with selected preview and supported actions | Context overlay parity |
| long-press reply uses the existing quote-reply path | Long-press reply |
| long-press copy action copies exact text and dismisses once | Clipboard copy |
| local-only long-press actions remain available when reactions are unavailable | No-reaction local actions |
| long-press reaction selection preserves the reaction path | Reaction parity |
| passes isSending through to the compose send affordance | Send state |
| group rows keep a single glass shell across text, quote, reaction, and media variants | Single-shell row rendering |
| row shell stays single after reaction and media enrichment updates | Shell stability after enrichment |
| renders active quote preview and dismisses it | Quote preview |
| upload banner shows cancel affordance only when supplied | Cancel affordance |
| shows loading shell while initial group page is still loading | Loading state |
| shows empty state once group load completes with no messages | Empty state |
| IR-018 shows recovering state instead of current empty state during replay catch-up | Recovery banner + loading shell while replay drains |
| IR-018 keeps visible messages live while marking the group as recovering | Recovery banner does not hide live message rows |
| hides compose area for readers in announcement group | Read-only mode |
| shows dissolved read-only copy and badge for ended groups | Dissolved state |
| IR-016 shows expired backlog banner and empty-state override after retention expiry | Retention banner |
| IR-016 shows mixed-window retention banner while retained messages stay visible | Retention + messages |
| composer listenable updates do not rebuild header or message list | Rebuild isolation |
| failed outgoing media rows show retry and delete controls | Failed media UI |
| renders text plus video, voice, and failed media rows visibly | GMAR-004 visible video/voice/failed-media rows remain present across rebuild/reopen-style rendering |
| incoming, text-only, and read-only announcement rows do not show failed-media controls | Negative UI check |
| KE-022 renders key-update recovery placeholder as a visible degraded state | Pending-key recovery placeholder visible without failed-media controls |
| wraps incoming messages with swipe-to-quote when enabled | Swipe to quote |
| does not wrap outgoing messages with swipe-to-quote | Outgoing guard |
| does not wrap incoming messages with swipe-to-quote for readers | Reader guard |
| renders quoted replies from existing parent messages | Quote rendering |
| renders unavailable fallback when quoted parent is missing | Missing parent |
| resolves quoted media-only parent from mediaMap | Media quote |
| GE-024 renders available and unavailable quote parents without crashing | Quote-parent entitlement fallback/no-crash across membership boundary |

### 5.8 GroupConversationWired
**File:** `test/features/groups/presentation/group_conversation_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupConversationWired` | prefills shared text into the group composer | Share intent |
| | hydrated group initialPendingMedia uses budget bytes instead of file size | Media budget |
| | oversized gallery attachment compresses under budget and stages the processed file | Compression |
| | oversized gallery attachment that remains over budget after compression leaves no pending state | Over-budget guard |
| | blocks a second text send while the first local send is in flight and releases after success | Send lock |
| | voice send blocks text send while the voice pipeline is active and releases after failure | Voice lock |
| | media uploads pre-persist upload_pending rows and start in parallel from durable copies | Durable media |
| | ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage | Pre-persist |
| | failed media upload leaves durable pending rows retryable and avoids group publish | Upload failure |
| | ordinary media upload failure persists failed parent state and restores composer and quote | Failure recovery |
| | ordinary media group-not-found rejection removes the row and cleans durable media state | Not-found cleanup |
| | ordinary media unauthorized rejection removes the row and cleans durable media state | Auth cleanup |
| | non-durable media send reuses optimistic attachment IDs when uploader returns different IDs | ID reuse |
| | sending a message with zero topic peers keeps the row sent and does not restore the draft | Zero-peer send |
| | incoming message stream upserts without full message/media reloads | Upsert optimization |
| | GP-027 out-of-order live messages keep deterministic order after restart | Deterministic timeline ordering for live out-of-order arrival and persisted reload |
| | swipe-to-reply sends quotedMessageId and clears preview | Quote send |
| | live removal timeline event from listener appears in UI | Removal timeline |
| | live re-add timeline event from listener appears in UI | Re-add timeline |
| | shows loading shell until the initial group page resolves | Loading state |
| | IR-018 shows recovery state while restart replay is pending and live messages still arrive | Wired recovery gate banner with live-message delivery |
| | highlights the targeted message context when opened from a notification anchor | Notification anchor + long-press parity |
| | notification-anchor entry keeps group reaction inspection aligned with the shared conversation surface | Notification anchor reaction parity |
| | incoming message preserves scroll offset when reading older messages | Scroll preservation |
| | recording ticks update composer without rebuilding header or message list | Rebuild isolation |
| | voice record callbacks switch the group composer into and out of recording | Voice recording |
| | loads and displays messages on init | Init loading |
| | sending a message calls bridge and refreshes | Send flow |
| | info button navigates to group info | Navigation |
| | returning from group info reloads the latest group name | Name reload |
| | non-admin in announcement group cannot write | Read-only mode |
| | dissolved groups show read-only copy and no send controls | Dissolved state |
| | announcement readers stay read-only for compose but still keep reaction entry | Reaction-entry parity |
| | dissolved groups hide reaction entry even when reaction deps are wired | Dissolved reaction-entry guard |
| | stale reaction entry restores local state when the group dissolves before publish | Dissolve race recovery |
| | non-admin in announcement group still has no voice stop/cancel callbacks when durable voice deps are enabled | Voice guard |
| | read-only announcement members cannot keep hidden quote state | Quote guard |
| | stale writer callbacks cannot bypass read-only announcement mode | Stale callback guard |
| | current group removal shows a notice and exits the conversation route | Removal exit |
| | gallery multi-video batches keep one processing tile with honest batch context | Multi-video |
| | sent text message appears immediately before bridge responds | Optimistic UI |
| | publish timeout with inbox success keeps the message successful in UI | Timeout + inbox |
| | sets tracker active on init | Tracker init |
| | clears tracker on dispose | Tracker cleanup |
| | accepts empty initialAttachments without error | Empty attachments |
| | recorded single video keeps single-item processing copy | Video processing |
| | optimistic message is saved to DB before network ops | Pre-persist |
| | failed publish shows message with failed status | Failure UI |
| | upload failure restores quote draft and attachments | Quote restoration |
| | shows relay upload progress and blocks leaving mid-upload | Upload progress |
| | retry control re-sends only the targeted failed outgoing media row | Targeted retry |
| | GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates | Reopen hydration keeps completed/pending/failed media metadata, one row/attachment set, and scoped unavailable-media retry wiring |
| | delete control removes only the targeted failed media row and owned files | Targeted delete |
| | publish failure restores quote draft and attachments | Quote restoration |
| | voice send path stays hidden unless both durable media dependencies exist | Voice deps guard |
| | voice stop pre-persists a durable pending attachment and threads a stable blob ID | Voice pre-persist |
| | voice upload failure keeps upload_pending retry data and restores the quote | Voice failure |
| | successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion | Voice success |
| | voice record stop keeps the optimistic voice row caller-local until upload completes | Voice optimistic |
| | voice send with zero topic peers still persists the final row as sent | Voice zero-peer |
| | voice group-not-found rejection does not leave a persisted outgoing row | Voice not-found |
| | voice stop cleanup still runs after unmount when group lookup resolves to not found | Voice cleanup |
| | voice upload failure restores the quoted reply target | Voice quote restore |
| | voice publish failure restores the quoted reply target | Voice quote restore |
| | announcement admin sees mic button for voice recording | Announcement voice |
| | loads persisted reactions on init when reactionRepo is provided | Reaction loading |
| | local long-press actions stay available when reactionRepo is null | No-reaction long-press parity |
| | incoming reaction change stream updates UI state | Reaction stream |
| | group reaction chips open participant inspection without mutating stored reactions | Reaction inspection + non-destructive tap |
| | group reaction inspection resolves member usernames and readable peer-id fallback | Reaction identity resolution |

### 5.9 GroupConversationWired Background Task
**File:** `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

| Group | Test | What it covers | Notes |
|-------|------|----------------|-------|
| `GroupConversationWired Section 3 background-task protection` | bg:begin happens before media upload and bg:end happens after publish and inbox store | Background task lifecycle | Active; AN-008 direct evidence; `group:inboxStore` command issuance/started-before-cleanup only, not durable completion-before-cleanup |
| | bg:end fires on media upload failure early return | Upload failure cleanup | Active; AN-008 direct evidence |
| | bg:end fires when upload throws | Upload throw cleanup | Active; AN-008 direct evidence |
| | send proceeds normally when OS refuses background task | OS refusal resilience | |
| | bg:end fires when widget unmounts mid-send | Unmount cleanup | |
| | ordinary media upload failure after unmount still persists failed parent status | Unmount failure persistence | |
| | text-only send acquires background task before publish | Text send protection | |
| | voice send path is background-task protected | Voice send protection | |
| | announcement voice-only send uses durable path, exact push body, and sent status when no peers are live | Announcement voice zero-peer | |
| | ordinary group text send stays bg-task protected across lock/unmount with peers | Text send lock/unmount | |
| | ordinary group text send returns sent after lock/unmount when topic peers are zero | Text send zero-peer | |
| | announcement admin text send stays bg-task protected across lock/unmount with peers | Announcement text lock/unmount | |
| | announcement admin text send returns sent after lock/unmount when topic peers are zero | Announcement text zero-peer | |
| | announcement media send preserves messageId, key epoch, and media metadata through wired path | Announcement media metadata | Active; AN-008 direct evidence |
| | order-recording bridge proves no early cleanup | Bridge ordering | Active; AN-008 direct evidence; live-peer inbox response may finalize after `bg:end`, but `group:inboxStore` command issuance starts before cleanup |

### 5.10 GroupInfoScreen
**File:** `test/features/groups/presentation/group_info_screen_test.dart`

| Test | What it covers |
|------|----------------|
| shows members | Member rendering |
| uses UserAvatar for each member row | Avatar consistency |
| keeps fallback identity readable when no avatar photo exists | Readable avatar fallback |
| shows roles | Role rendering |
| shows leave button | Leave CTA |
| shows dissolve button for active admins | Dissolve CTA |
| shows mute switch state | Mute toggle |
| calls onMuteChanged when mute switch is toggled | Mute callback |
| shows Add Member button when isAdmin | Add-member CTA |
| hides Add Member button when not admin | Add-member guard |
| calls onAddMember callback when tapped | Add-member callback |
| shows invite status and send again only for needs resend | Invite status badge and manual resend action visibility |
| shows role-management controls only for eligible admin rows | Role controls |
| shows Edit Details button when admin can edit metadata | Edit CTA |
| hides Edit Details button when viewer is not admin | Edit guard |
| dissolved groups show local cleanup and hide management controls | Dissolved local cleanup |

### 5.11 GroupInfoWired
**File:** `test/features/groups/presentation/group_info_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupInfoWired` | loads and displays group members on init | Init loading |
| | loads invite delivery statuses for member rows | Invite status hydration |
| | shows Add Member button for admin role | Add-member CTA |
| | shows the creator username from the real create flow for other members | Creator identity rendering |
| | hides Add Member button for non-admin role | Add-member guard |
| | admin can dissolve a group and the screen switches to read-only state | Dissolve flow |
| | toggles mute state and persists it to the repository | Mute toggle |
| | hides member remove controls for non-admin role | Remove guard |
| | uses repo myRole instead of stale navigation role on load | Fresh role |
| | admin metadata edit updates repo state, timeline, and bridge payloads | Metadata edit + actor keys + config hash |
| | promote member shows confirmation, updates badge, and emits member_role_updated payload | Promote flow |
| | demote admin shows confirmation, updates badge, and emits success feedback | Demote flow |
| | dissolved local delete clears local state without publishing group leave and pops to the first route | Local-only cleanup flow |
| | canceling dissolved local delete keeps the group state and route intact | Local-delete cancel guard |
| | leave group calls bridge and pops to first route | Leave flow |
| | sole admin leave stays on screen and shows an error | Sole-admin guard |
| | multi-admin leave broadcasts self-removal, rotates key, and pops to first route | Multi-admin leave |
| | writer leave broadcasts a durable left-the-group event before local cleanup | Voluntary leave timeline |
| | remove member updates config and refreshes member list | Remove flow |
| | remove member broadcasts system message and rotates key | Remove side-effects |
| | remove member calls bridge in correct order: updateConfig -> publish -> inboxStore -> generateNextKey | Bridge command order |
| | remove member distributes rotated key to remaining members via P2P | Key distribution |
| | remove member broadcast and replay artifact contain correct member_removed payload | Payload shape |
| | canceling remove member keeps membership unchanged | Cancel guard |
| | stale non-member removal shows error and emits no removal side effects | Stale member guard |

### 5.12 CreateGroupPickerScreen
**File:** `test/features/groups/presentation/create_group_picker_screen_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `CreateGroupPickerScreen` | renders header with New Group title | Header text |
| | renders search field | Search UI |
| | renders contact rows | Contact list |
| | shows empty state when no contacts | Empty state |
| | search filters contacts by username | Search filter |
| | tapping contact calls onToggle | Toggle callback |
| | GroupNamePanel hidden when no contacts selected | Panel visibility |
| | GroupNamePanel visible when contacts selected | Panel visibility |
| | back button calls onBack | Back callback |
| | shows loading state when isCreating | Loading state |

### 5.13 CreateGroupPickerWired
**File:** `test/features/groups/presentation/create_group_picker_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `CreateGroupPickerWired` | loads and displays active contacts | Init loading |
| | excludes self from contact list | Self exclusion |
| | tapping contact toggles selection | Toggle |
| | panel appears after selecting a contact | Panel visibility |
| | tapping Start group chat creates group and navigates to conversation | Create flow |
| | announcement picker route creates announcement group and sends announcement payload | Announcement create |
| | shows an explicit warning when create succeeds with invite degradation | Degraded create feedback |
| | shows error snackbar on failure | Error feedback |
| | shows a size-limit snackbar when create selection exceeds the contract | Limit feedback |
| | back button pops screen | Navigation |

### 5.14 ContactPickerScreen
**File:** `test/features/groups/presentation/contact_picker_screen_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerRow` | renders username | Row rendering |
| | calls onTap when tapped | Tap callback |
| | shows check_circle when isSelected is true | Selected state |
| | shows add_circle_outline when isSelected is false (default) | Unselected state |
| `ContactPickerScreen` | renders header with title and back button | Header rendering |
| | renders list of contacts | List rendering |
| | shows empty state when no contacts available | Empty state |
| | calls onToggle when contact is tapped | Toggle callback |
| | calls onBack when back button is tapped | Back callback |
| | header shows "Add Members (N)" when contacts are selected | Selected count |
| | header shows "Add Member" when nothing selected | Default header |
| | shows check_circle for selected contacts in list | Selection UI |
| | shows Send Invites button when 1+ selected | Invite CTA |
| | hides Send Invites button when none selected | CTA guard |
| | calls onConfirm when Send Invites tapped | Confirm callback |
| | search still works in multi-select mode | Search + select |
| | shows loading indicator when isInviting | Loading state |

### 5.15 ContactPickerWired
**File:** `test/features/groups/presentation/contact_picker_wired_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerWired` | shows contacts excluding existing group members | Member exclusion |
| | excludes self from contact list | Self exclusion |
| | tapping contact toggles selection state | Toggle |
| | confirm button appears after selecting one contact | CTA visibility |
| | header shows selected count | Count display |
| | batch invite adds all selected members to DB | Batch persist |
| | batch invite broadcasts one members_added system message | System message |
| | batch invite sends individual P2P invites to each contact | P2P invites |
| | batch invite pops with an explicit completion result | Pop result |
| | back button pops with 0 | Cancel pop |
| | shows error snackbar when invite fails | Error feedback |
| | stale duplicate selection fails without config sync or members_added publish | Stale dedup |
| | over-limit batch selection fails without partial members or config sync | Over-limit guard |
| | invite keeps local membership but reports explicit warning details when delivery fails | Invite warning feedback |
| | reports the current key generation when invite encryption succeeds | Key proof |
| | invite skips sendGroupInvite when no group key exists | Missing key skip |
| | batch invite with no group key still adds members locally | Local-only add |
| | batch invite saves a durable members-added timeline locally | Durable add timeline |

### 5.16 ContactPicker Multi-Select Integration
**File:** `test/features/groups/presentation/contact_picker_multi_select_integration_test.dart`

| Test | What it covers |
|------|----------------|
| multi-select integration: full batch invite flow | End-to-end batch invite |

### 5.17 GroupNamePanel
**File:** `test/features/groups/presentation/widgets/group_name_panel_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupNamePanel` | renders overlapping UserAvatars for selected contacts | Avatar rendering |
| | displays comma-separated usernames | Username list |
| | shows group name text field with placeholder | Name field |
| | shows Start group chat button | Start CTA |
| | calls onStartGroup when button tapped | Start callback |
| | passes text field value to nameController | Name binding |
| | shows loading indicator when isCreating | Loading state |
| | renders correctly with 1 contact | Single contact |
| | displays +N suffix for 3+ contacts | Overflow suffix |

### 5.18 ExpandableFab
**File:** `test/features/groups/presentation/widgets/expandable_fab_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ExpandableFab` | initially shows + icon (closed state) | Default state |
| | tapping FAB opens menu and shows x icon | Open state |
| | shows all menu item labels when open | Menu labels |
| | hides menu item labels when closed | Hidden labels |
| | calls item callback when menu item tapped | Item callback |
| | closes menu after item is tapped | Auto-close |
| | tapping x closes the menu | Close action |
| | shows scrim overlay when open | Scrim overlay |
| | defaults to bottom-right positioning | Default position |
| | positions at top-right when anchor is topRight | Alt position |
| | menu items appear below FAB when anchor is topRight | Alt layout |
| | passes fabSize to GlowFab | Size pass-through |

### 5.19 GlowFab
**File:** `test/features/groups/presentation/widgets/glow_fab_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GlowFab` | renders + icon by default | Default icon |
| | renders custom icon when provided | Custom icon |
| | calls onPressed when tapped | Tap callback |
| | defaults to 56 when no size given | Default size |
| | uses custom size when provided | Custom size |
| | has circular shape with blue border | Shape + border |

### 5.20 ContactPickerRow
**File:** `test/features/groups/presentation/widgets/contact_picker_row_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ContactPickerRow` | renders UserAvatar with contact peerId | Avatar rendering |
| | renders UserAvatar at size 36 | Avatar sizing |
| | displays contact username | Username display |
| | displays truncated peerId | PeerId display |
| | shows add_circle_outline icon when not selected | Unselected state |
| | shows check_circle icon when selected | Selected state |
| | calls onTap when tapped | Tap callback |

---

## 6. Integration Tests

### 6.1 Group Messaging Smoke
**File:** `test/features/groups/integration/group_messaging_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Multi-user group messaging smoke tests` | 3 users: basic fan-out -- sender does not receive own message | Fan-out + self exclusion |
| | 4 users: round-robin messaging -- all receive from all others | Full mesh |
| | GM-001 DE-001 creates private A/B/C group with shared epoch and exact fanout tuple | A/B/C live private text delivery with one sender-visible outgoing row, Bob/Charlie incoming rows, shared group id/message id/sender id/timestamp/key epoch, and no sender self-echo |
| | DE-006 full live fanout remains sent not delivered | Full live fanout keeps sender row at sent, never delivered, and creates no delivered/read receipt evidence |
| | GM-002 adds D while A/B/C are online and converges post-add delivery | Host fake-network add-D convergence and post-add delivery proof; non-closing without exact device E2E |
| | IR-006 KE-021 removed member is not targeted by future fake-network key or inbox payloads | Host fake-network proof that removed C is unsubscribed and remains on epoch 1 while future direct key-update payloads, `group:inboxStore` recipients, and the epoch-2 post-removal live message target only remaining Bob while excluding Alice/removed/declined/expired/never-joined peer ids |
| | KE-022 failed key update exposes diagnostics and recovery placeholder over fake network | Host fake-network proof that direct key-update failure keeps Bob on the old epoch, requests key repair with `key_update_apply_failed`, attempted epoch-2 receive emits live diagnostic repair, and saves a pending-key placeholder |
| | simultaneous sends fan out to the third member without loss | Concurrent fan-out |
| | DE-002 rapid 100 same-sender messages stay ordered for both recipients | Per-sender ordering for a 100-message Alice burst across Bob, Charlie, and Alice's outgoing rows |
| | message to unknown group is ignored | Unknown group guard |
| | late joiner receives messages only after joining | Late-join boundary |
| | sender saves outgoing locally and others save incoming | Direction persistence |
| | quoted reply propagates to all recipients | Quote fan-out |
| | message is received after app restart with rejoin | Rejoin recovery |
| | GE-021 large group with one flaky member preserves stable delivery | Large 11-member group stable delivery through flaky member offline/online and remove/readd churn |
| | GE-023 media attachments in private group through remove/re-add respect entitlement | Media attachment entitlement through remove/readd with removed-window exclusion |
| | GE-024 quoted replies across membership boundary preserve entitlement fallback | Quote parent entitlement/fallback through remove/readd boundary |

### 6.2 Group Membership Smoke
**File:** `test/features/groups/integration/group_membership_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Multi-user group membership smoke tests` | admin removes member -- removed member stops receiving messages | Removal enforcement |
| | admin removes member -- remaining members update their local member list | Member list sync |
| | non-admin raw membership removal event is ignored by peers | Auth guard |
| | self-removal -- removed user calls leaveGroup and cleans up | Self-removal |
| | sole admin cannot leave while only writer members remain | Sole-admin guard |
| | promoted admin gains admin role and can perform admin-only actions | Promotion flow |
| | multi-admin leave keeps remaining admin healthy and synchronized | Multi-admin leave |
| | concurrent admin changes converge to one final member/admin map | Concurrent convergence |
| | GE-016 two admins mutate membership concurrently and converge | Concurrent admin mutation convergence and cleanup |
| | conflicting remove and promote of the same member converge to removal | Conflict resolution |
| | removed member cannot send after self-removal cleanup | Post-removal send guard |
| | remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff | Cutoff enforcement |
| | add member syncs every member list and the new member can participate | Add-member sync |
| | writer leave emits a durable left-the-group event for remaining members | Voluntary leave timeline |
| | duplicate re-add returns error and leaves member lists unchanged | Duplicate guard |
| | non-member removal returns error and leaves member lists unchanged | Non-member guard |
| | new member cannot send before bootstrap key exists, then succeeds after bootstrap completes | Bootstrap key |
| | post-removal messaging -- admin can still send to remaining members | Post-removal send |
| | remaining member receives readable removal timeline event while member list updates | Timeline event |
| | removed member can be re-added with current state and resumes send/receive | Re-add flow |
| | IR-005 GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages | Fake-network remove/re-add replay boundary: Charlie keeps allowed pre-removal and post-readd history while removed-window plaintext stays excluded |
| | removed member notifications stay off until rejoin becomes effective | Notification guard |
| | long mixed-content group text survives delivery and notification preview | Long message |
| | remaining member receives readable re-add timeline event while member list updates | Re-add timeline |
| | GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others | Offline dissolve + local cleanup |

### 6.3 Group Edge Cases Smoke
**File:** `test/features/groups/integration/group_edge_cases_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group edge cases and fault injection smoke tests` | delivery failure -- messages not delivered when network fails | Network failure |
| | duplicate delivery -- GroupMessageListener handles idempotently | Dedup |
| | delivery delay -- messages arrive after delay | Delayed delivery |
| | 5 users simultaneous messaging -- high fan-out | High fan-out |
| | leave group voluntarily -- user stops receiving | Voluntary leave |
| | rapid message burst -- 20 messages from single sender | Burst handling |
| | network counters track publish and delivery correctly | Counter accuracy |

### 6.4 Startup Rejoin Smoke
**File:** `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Startup rejoin smoke tests` | rejoin topics then receive live messages after simulated restart | Rejoin + live delivery |
| | rejoin + drain handles groups with no offline messages | Empty drain |
| | rejoin sends correct groupConfig with all member public keys | Config correctness |

### 6.5 Group Reaction Roundtrip
**File:** `test/features/groups/integration/group_reaction_roundtrip_test.dart`

| Test | What it covers |
|------|----------------|
| chat-group reaction roundtrip reaches the original sender through the live listener stream | Reaction fan-out |

### 6.6 Multi-Device Convergence
**File:** `test/features/groups/integration/group_multi_device_convergence_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `same-user multi-device convergence` | joined sibling device stores same-user live publish as local sent history | Multi-device sent history |
| | same-user sibling devices can send concurrently without id collision loss | Same-user concurrent send identity |
| | joined sibling device converges membership updates without duplicate local membership | Membership convergence |
| | sibling device stays one member while new human admission adds a distinct member | IJ-012 sibling-device versus new-human admission distinction |
| | device-local unsubscribe preserves member account and sibling delivery | RP-010 fake-network device-local unsubscribe |
| | mute, unread, and local notifications stay device-local across joined sibling devices | Device-local state |

### 6.7 Group Resume Recovery
**File:** `test/features/groups/integration/group_resume_recovery_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group resume recovery integration tests` | member backgrounded during send receives missed group messages after resume | Background resume |
| | same message is not duplicated if both pubsub and group inbox deliver it | Cross-path dedup + content preservation |
| | DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence | Fake-network live delivery plus listener-backed inbox replay preserves one visible row and one stream insertion while committing replay read/local-delivered receipt evidence |
| | DE-005 sender self echo plus inbox duplicate reconciles pending row once | Fake-network sender self echo plus inbox duplicate promotes one pending outgoing row to sent without adding an incoming duplicate |
| | DE-006 partial live fanout does not claim offline recipient receipt before inbox drain | Partial live fanout keeps offline recipient unreached before replay, creates no sender delivered/read receipts before or after inbox drain, and later replays exactly once |
| | DE-007 zero-peer publish reaches active Bob and Charlie through replay | Active Bob and Charlie are outside the topic mesh, receive no live row before replay, then each persist Alice's stored message exactly once after durable inbox drain |
| | IR-007 DE-008 publish failure branch retries over fake network with same id and one row | Test-local BRIDGE_TIMEOUT plus failed custody leaves one failed sender row, then failed-message retry sends the same id and recipient persists exactly one row |
| | IR-007 rapid pause/resume closes pending live-peer send via inbox retry exactly once | Publish-success plus failed inbox custody leaves one pending sender row owned by inbox retry, resume retries it once, and live/offline readers each see one row |
| | IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once | First fake-network cursor retrieve failure leaves no message, cursor, or receipt side effect, then retry requests the same cursor and drains the missed message once |
| | IR-009 failed replay persistence retries same cursor and stores missed fake-network message once | First fake-network local replay persistence failure leaves no message, cursor, or receipt side effect, then retry requests the same cursor and stores the missed message once |
| | IR-011 fake-network history repair validates request identity and source peer before mutation | Fake-network resume recovery skips wrong-group gaps and unauthorized sources, rejects wrong group/gap/source repair responses, and stores only the valid fallback repaired message |
| | IR-012 fake-network repair rejects wrong hash and head then restores range before live delivery | Fake-network repair rejects bad-hash and wrong-head sources, falls back to a valid source, restores ordered repaired messages, and accepts later live delivery |
| | IR-013 fake-network unauthorized repair source cannot inject before fallback | Fake-network resume recovery skips unauthorized repair candidates, rejects forged returned-source responses, sends repair requests only to authorized sources, and stores only the authorized fallback repaired message |
| | IR-014 fake-network inbox store relay payload is opaque while delivery succeeds | Fake-network delivery succeeds while the relay-visible inbox-store command remains routing-limited and excludes protected plaintext, sender display name, group key, invite/member secrets, and retired push preview fields |
| | IR-015 fake-network replay drains text quote image video file GIF and voice uniformly | Offline Bob drains all variant replay messages exactly once across repeat drains while preserving quote target, key epoch, and image/video/file/GIF/voice media descriptors |
| | DE-012 dispatcher overflow diagnostic drains inbox replay for a dropped group message | Fake-network overflow diagnostic triggers offline inbox drain so a dropped live group message is replayed and persisted exactly once |
| | IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event | Overflow-triggered replay restores the dropped inbox message exactly once and a second overflow-triggered drain does not duplicate it |
| | IR-018 restart recovery keeps recovering state until replay drains and live stays active | Fake-network restart recovery keeps the recovery gate active during a blocked replay drain, accepts live delivery during recovery, drains replay before ack, and persists live plus replay exactly once |
| | IR-019 fake-network replay dedupes by decrypted payload id without outer id | Fake-network live delivery followed by hidden-id cursor replay keeps one recipient row, preserves trusted live content/timestamp, advances the cursor, and emits no duplicate listener/UI row |
| | DE-013 malformed pubsub message is rejected and later valid delivery persists | Fake-network malformed group event creates no row, emits schema rejection evidence, and a later valid pubsub message persists exactly once |
| | DE-014 decrypt failure repairs from durable replay and preserves later fake-network delivery | Fake-network live decrypt diagnostic creates a placeholder, durable replay queues a pending-key repair row, key arrival repairs the row, and later live delivery still persists exactly once |
| | DE-015 payload parse diagnostic does not poison later fake-network delivery | Fake-network payload-parse diagnostic creates no visible row and later valid delivery persists exactly once |
| | DE-016 validation reject diagnostic stays safe and later fake-network delivery persists | Fake-network validation-reject diagnostic creates no visible row and later valid delivery persists exactly once |
| | DE-017 out-of-order membership and content converges to membership interval | Fake-network out-of-order member add/content and removal/content delivery converges to the sender's membership interval |
| | DE-020 large payload does not starve later fake-network delivery | Max-length group text and a normal follow-up fake-network send both persist exactly once, in send order, without losing the later message |
| | IR-003 timestamp replay boundary drains same-ms fake-network messages once | Fake-network replay preserves inclusive timestamp boundary and exact-once same-ms/adjacent delivery |
| | live reaction replay on resume keeps a single truthful stored reaction after rejoin | Reaction replay dedupe after resume |
| | post-rotation reaction replay after rejoin keeps the truthful reactor on the rotated message | Post-rotation reaction recovery |
| | removed offline member drains replayed removal, loses group access, and cannot send after resume | Offline removal |
| | offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume | Cutoff + resume |
| | watchdog restart rejoins topics and receives subsequent live messages | Watchdog rejoin |
| | announcement reader backgrounded during send receives missed announces after resume | Announcement resume |
| | zero-peer inbox failure stays owned by failed-message retry and recovers in place | Zero-peer retry ownership |
| | MM-012 acceptance uses real GroupConversationWired sender path to keep discussion sendable and announcement admin blocked during active recovery | Recovery send contract |
| | 10-A acceptance uses real GroupConversationWired sender path with reader lifecycle inbox recovery | Announcement wired send |
| | announcement media send with zero topic peers stays sent and readers recover intact media refs after resume | Zero-peer media |
| | 10-B acceptance uses real GroupConversationWired sender path for media + resume fallback | Media resume |
| | 10-C acceptance uses real GroupConversationWired sender path for voice + exact push body | Voice send path |
| | announcement admin send after key rotation uses the new epoch and remains deliverable | Post-rotation send |
| | 10-F acceptance uses real GroupConversationWired sender path after key rotation | Rotation + wired |
| | group discovery remains live across ttl refresh window without manual rejoin | Discovery TTL |
| | fake group network delivers live messages without explicit relay simulation | Test infra validation |
| | many joined groups resume without bursting recovery work all at once | Batch throttle |
| | resume drains missed group backlog exactly once across pages | Multi-page drain |
| | multi page backlog uses cursor continuation without duplication | Cursor pagination |
| | multi page replay with a tampered timestamp still keeps one stored row | Replay tamper dedup across pages |
| | IR-016 long-offline mixed-window recovery keeps retained backlog and explicit cutoff state | Retention enforcement with explicit expired/retained cutoff state |
| | watchdog restart rejoins topics and resumes live delivery | Watchdog recovery |
| `Section 11 test infrastructure` | publish with zero peers falls back to inbox | Zero-peer fallback |
| | GP-007 zero-peer send delegates to inbox without visible delay | Zero-peer bounded send |
| | inbox store failure doesn't block publish | Inbox error isolation |
| | rapid pause/resume closes a pending live-peer send via inbox retry exactly once | Rapid lifecycle |
| | stuck sending recovery after background | Stuck recovery |
| | partial delivery with inbox drain completion | Partial drain |
| | temporary partition replays missed backlog in cursor order and resumes live delivery after heal | Partition heal |
| | full lifecycle round-trip | End-to-end lifecycle |
| | failed message retry after network recovery | Network retry |
| | DE-003 caller-supplied message id survives live replay and retry | Stable caller message id across live receive, replay dedupe, and retry |
| | unread count stays correct across duplicate inbox drain, retry recovery, and read clear | Unread accuracy |
| | offline member reconnects after membership churn and converges to the final member list | Churn convergence |
| | offline member reconnects after repeated metadata edits and converges to the final metadata state | Metadata convergence |
| | multi-group resume doesn't burst all recovery at once | Multi-group throttle |

### 6.8 Invite Round-Trip
**File:** `test/features/groups/integration/invite_round_trip_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Group invite round-trip integration` | full invite round-trip: admin sends invite -> receiver processes it -> group is persisted | End-to-end invite |
| | new member history stays future-only while post-join replay is allowed | History boundary |
| | remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch | Re-invite after rotation |
| | offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch | Offline re-invite |
| | full round-trip with PassthroughCryptoBridge verifies | Crypto round-trip |
| | receiver rejects invite from unknown sender (not in contacts) | Unknown sender guard |
| | receiver rejects duplicate invite for group already joined | Duplicate guard |
| | invite round-trip with multiple members in config | Multi-member config |
| | GroupInviteListener stores pending invite and explicit accept completes the join flow | Pending accept flow |
| | accept publishes a durable join event that existing members can render | Durable join timeline |
| | bridgeError accept later rejoin and drain converge without the pending invite row | Accepted-but-degraded later recovery |
| | concurrent pending accepts converge members, key epoch, and sendability | IJ-010 concurrent accept convergence |

### 6.9 Announcement Happy Path
**File:** `test/features/groups/integration/announcement_happy_path_test.dart`

| Test | What it covers |
|------|----------------|
| announcement happy path: create, admin send, reader read-only receive, member react | Full announcement lifecycle |
| announcement admin can send GIF media and reader receives image/gif read-only | GIF announcement |

### 6.10 Group New-Member Onboarding
**File:** `test/features/groups/integration/group_new_member_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Group new-member onboarding` | new member receives only post-join text and media with descriptors | Discussion post-join text/image/video/voice, no pre-join backfill, descriptor persistence, media-download trigger |
| | multiple newly-added members converge on latest epoch and receive the same post-add message | Multi-add same-epoch convergence |
| | multiple newly-added members independently download the same post-join image, video, and voice without pre-join history | GMAR-003 Bob/Charlie same post-join image/video/voice completed downloads with sender/message/epoch/attachment metadata, exact per-recipient download calls, and no pre-join text/media rows, attachments, pending downloads, or pre-join media download calls |
| | new member receives current metadata and roles without pre-join history | IJ-011 current metadata, role snapshot, and future-only history |
| | add-send boundary delivers only after the new member is subscribed | Deterministic add/send boundary |
| | new member receives post-join reactions without pre-join reaction state | Reaction fan-out to newly-added member |
| | quoted reply to pre-join parent keeps missing-parent fallback for new member | Post-join quote with unavailable pre-join parent |

### 6.11 Announcement New-Reader Onboarding
**File:** `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Announcement new-reader onboarding` | new reader receives only post-join admin media with descriptors | Announcement image/video/voice delivery to newly-added reader, no pre-join admin-post backfill, media-download trigger |

### 6.12 Existing-Member Group Media Fan-Out
**File:** `test/features/groups/integration/group_media_fanout_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `Existing-member group media fan-out` | discussion members independently download image, video, and voice for every eligible recipient | Existing Bob/Charlie receive Alice's image/video/voice rows with matching sender message ids and attachment metadata; both independently complete downloads with local paths and exactly three `media:download` calls each |
| | one recipient media download failure remains observable per recipient | A forced Charlie image download failure remains `failed`/non-done with no local path while Bob's image/video/voice and Charlie's video/voice downloads remain done |
| | MD-011 removed member is excluded from future media descriptors and downloads | After removal and epoch-2 rotation, remaining B receives/downloads future media while removed C has no descriptor, message, media row, pending download, download/decrypt bridge call, subscription, or future key |
| | newly-added discussion member media reaches every eligible recipient | GMAR-003 newly-added Bob sends image/video/voice after bootstrap; Alice and Charlie receive exact-once rows with Bob sender identity, sender message ids, key epoch, attachment metadata, completed downloads, and exactly three `media:download` calls each |
| | existing non-creator discussion member media reaches creator and every eligible recipient | GMAR-003 existing non-creator Charlie sends image/video/voice; Alice and Bob receive exact-once rows with Charlie sender identity, sender message ids, key epoch, attachment metadata, completed downloads, and exactly three `media:download` calls each |

---

## 7. Core Layer (Lifecycle & Bridge)

### 7.1 handleAppPaused (groups)
**File:** `test/core/lifecycle/handle_app_paused_group_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppPaused for groups` | transitions group alongside 1:1 | Parallel transition |
| | group error isolation leaves 1:1 transition intact | Error isolation |
| | null groupMsgRepo keeps pause handler backward compatible | Null compat |
| | group-only pending sends still transition when 1:1 count is zero | Group-only path |

### 7.2 handleAppResumed (group inbox retry)
**File:** `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`

| Test | What it covers |
|------|----------------|
| resume handler Step 8e calls retryFailedGroupInboxStoresFn | Inbox retry wiring |
| resume handler Step 8e is fault-isolated from Step 8d | Error isolation |
| resume handler continues normally when retryFailedGroupInboxStoresFn is null | Null compat |

### 7.3 handleAppResumed (group recovery)
**File:** `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppResumed group recovery` | calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores | Full recovery sequence |
| | feature gate disables group recovery callbacks | Feature gate |
| | blocks admin-only group actions until replayed membership removal settles | Recovery lock |
| | IR-018 recovery gate stays active until pending replay drain completes | Recovery gate remains active and ack stays withheld while replay drain is blocked |

### 7.4 handleAppResumed (group stuck sending)
**File:** `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleAppResumed -- group stuck sending recovery` | calls rejoin, drain, recoverStuck, then retryFailed | Recovery sequence |

### 7.5 main resume group upload wiring
**File:** `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

| Test | What it covers |
|------|----------------|
| main.dart passes mediaFileManager into retryIncompleteGroupUploads on resume | DI wiring |
| main.dart passes mediaAttachmentRepository into retryFailedGroupMessages on resume | DI wiring |
| main.dart wires group retry callbacks into PendingMessageRetrier | Retry wiring |
| main.dart binds the pending retrier overlap guard to _isResuming | Guard wiring |

### 7.6 Bridge Group Helpers
**File:** `test/core/bridge/bridge_group_helpers_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `callGroupCreate` | sends group:create with correct payload fields | Payload shape |
| | sends groupType NOT type in the payload (bug fix) | Field naming |
| | includes optional description when provided | Optional field |
| | excludes optional fields when null | Null omission |
| | returns parsed response on success | Response parsing |
| | returns error map on bridge error | Error handling |
| | returns timeout error on timeout | Timeout handling |
| | includes creatorMlKemPublicKey when provided | Key inclusion |
| | groupType field carries the correct value for different types | Type mapping |
| `callGroupKeygen` | sends group.keygen and returns key string on success | Keygen |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupPublish` | sends group:publish with correct payload and returns messageId | Publish |
| | returns error map on bridge error | Error handling |
| | returns timeout error on timeout | Timeout handling |
| | includes media in payload when provided | Media inclusion |
| | includes quotedMessageId when provided | Quote inclusion |
| | omits media when null | Null media |
| | omits media when empty list | Empty media |
| `callGroupEncrypt` | sends group.encrypt with key and plaintext | Encrypt |
| | returns timeout error map on timeout | Timeout handling |
| `callGroupDecrypt` | sends group.decrypt with key, ciphertext, and nonce | Decrypt |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupJoin` | sends group:join with groupId and topicName | Join |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupJoinWithConfig` | sends group:join with groupId, groupConfig, groupKey, keyEpoch | Join with config |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupAcknowledgeRecovery` | sends group:acknowledgeRecovery | Recovery ack |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupLeave` | sends group:leave with groupId | Leave |
| | completes without error on success | Success path |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupUpdateConfig` | sends group:updateConfig with groupId and full groupConfig | Config update |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupGenerateNextKey` | sends group:generateNextKey and returns key info | Key generation |
| | returns timeout error on timeout | Timeout handling |
| `callGroupRotateKey legacy helper` | sends group:rotateKey and returns key info | Legacy rotate |
| | returns timeout error on timeout | Timeout handling |
| `callGroupInboxStore` | sends group:inboxStore with groupId and message | Inbox store |
| | includes recipientPeerIds, pushTitle, and pushBody when provided | Push fields |
| | omits empty optional push fields | Null omission |
| | throws BridgeCommandException on ok:false | Error handling |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupInboxRetrieve` | sends group:inboxRetrieve and returns list of messages | Inbox retrieve |
| | returns empty list when no messages | Empty state |
| | returns empty list when messages field is null | Null guard |
| | throws BridgeCommandException on ok:false | Error handling |
| | rethrows TimeoutException on timeout | Timeout handling |
| `callGroupInboxRetrieveWithCursor` | encodes cursor and page metadata and returns next cursor | Cursor pagination |
| | IR-002 parses GroupInboxPage cursor metadata for paged replay | Cursor request encoding plus messages, next cursor, and history gap metadata parsing |
| | IR-010 parses and surfaces valid cursor historyGaps while filtering invalid entries | Valid cursor history gaps are parsed, invalid entries are ignored, and historyGapCount reflects accepted gaps |
| | rethrows TimeoutException on timeout | Timeout handling |
| | throws BridgeCommandException on ok:false | Error handling |

### 7.7 Go Bridge Client (group diagnostics and reinitialize subset)
**File:** `test/core/bridge/go_bridge_client_test.dart`

| Test | What it covers |
|------|----------------|
| DE-009 group message callback survives reinitialize and receives event once | Dart bridge callback preservation across `initialize()` then `reinitialize()` and exactly-once `group_message:received` routing |
| DE-018 unknown group event is ignored without blocking known callbacks | Unknown future `group:*` push event logs/ignores without known callbacks, then later group message and group reaction callbacks still fire exactly once |
| DE-019 EventChannel error emits diagnostics, recovers, and preserves group callback | EventChannel `onError` emits sanitized diagnostics, marks bridge unhealthy, resubscribes with a second listen, preserves the group callback, and delivers a post-recovery group message |
| DE-019 EventChannel done emits diagnostics, recovers, and preserves group callback | EventChannel `onDone` emits recovery diagnostics, resubscribes with a second listen, preserves the group callback, and delivers a post-recovery group message |
| DE-020 large group payload does not starve later group callback | Max-length group message text and a normal follow-up push event both reach `onGroupMessageReceived` once and in order |
| IR-011 history repair helper normalizes request identity and surfaces invalid input | Typed repair-range bridge payload trims request identity and surfaces native `INVALID_INPUT` for missing group, gap, or source identity |
| GO-004 group decryption failure diagnostic reaches repair stream without message callback | Owned Flutter decryption diagnostics without ghost message routing; preserves group/sender/epoch metadata and redacts plaintext/key/ciphertext/nonce fields |
| GO-004 group diagnostic stream redacts sensitive payload fields | Owned Flutter diagnostic sanitizer proof for ciphertext, nonce, peer id, secret key fragments, and multiaddr fragments |
| GO-008 group message raw flow logs metadata only without plaintext or sensitive payloads | Raw incoming group-message FLOW logging is bounded to metadata and omits plaintext, media keys, ciphertext, and group-key material |
| GO-008 diagnostic flow logs redact JSON-encoded sensitive payload strings | Diagnostic FLOW logs redact embedded JSON/key-value secrets before emission |
| DE-015 payload parse diagnostic does not poison later group message callback | Malformed payload diagnostics without ghost message routing plus later valid group-message callback continuity |
| DE-016 validation reject diagnostic reaches safe logs without group message callback | Validation-reject safe reason/hash/envelope/epoch fields reach `groupDiagnosticEventStream` and `GROUP_VALIDATION_REJECTED` flow logs without normal message callback routing |
| `BridgeCommandException on ok:false` | throws BridgeCommandException when group:join returns ok:false | Join error |
| | throws BridgeCommandException when group:join (with config) returns ok:false | Join-config error |
| | throws BridgeCommandException when group:leave returns ok:false | Leave error |
| | throws BridgeCommandException when group:updateConfig returns ok:false | Config error |

---

## 8. Cross-Feature Tests

### 8.1 groupMessagesIntoThreads (Feed)
**File:** `test/features/feed/domain/utils/group_messages_into_threads_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `groupMessagesIntoThreads` | empty input returns empty output | Empty state |
| | single unread incoming message produces unread state | Unread derivation |
| | sent + received messages both appear in thread | Bidirectional |
| | state derivation: unread -- unread incoming, no sent | State logic |
| | state derivation: active -- unread incoming + sent messages | State logic |
| | state derivation: replied -- all read + has sent | State logic |
| | state derivation: read -- all read, no sent | State logic |
| | 24-hour gap keeps single card per contact | Gap handling |
| | unread/active sort before read/replied | Sort priority |
| | exchangePreview returns last 2 messages | Preview window |
| | lastRepliedAt is set to latest sent message timestamp | Reply timestamp |
| | user sends first (no incoming) produces replied state | Send-first state |
| | ThreadMessage preserves isIncoming and status | Field preservation |
| | multiple contacts produce separate threads | Thread isolation |
| | blocked contact produces ThreadFeedItem with isBlocked=true | Block flag |
| | non-blocked contact produces ThreadFeedItem with isBlocked=false | Non-block flag |
| | quotedMessageId propagates to ThreadMessage | Quote propagation |
| | system messages are excluded from feed threads | System msg exclusion |
| | only system messages produces empty result | System-only guard |
| | burst within same contact stays in one thread | Burst handling |

### 8.2 groupGroupMessagesIntoThreads (Feed)
**File:** `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `groupGroupMessagesIntoThreads` | returns empty list when no messages | Empty state |
| | returns empty list when no groups | No groups |
| | creates one thread per group | Thread per group |
| | derives unread state when unread incoming with no sent | State logic |
| | derives active state when unread incoming + sent messages | State logic |
| | derives replied state when all read + sent messages | State logic |
| | derives read state when all incoming are read, no sent | State logic |
| | sorts unread/active before read/replied | Sort priority |
| | ignores messages for unknown groups | Unknown group |
| | messages sorted chronologically within thread | Sort order |
| | preserves group type in thread item | Type preservation |
| | preserves myRole and derives canWrite for announcement groups | Role + write flag |
| | preserves dissolved state and freezes write and reaction entry | Dissolved frozen-state projection |
| | preserves quotedMessageId on projected thread messages | Quote propagation |
| | thread id is group_thread_ + groupId | ID construction |
| | timestamp is latest message timestamp | Timestamp derivation |
| | ThreadMessage includes senderUsername and senderPeerId from GroupMessage | Sender fields |
| | multiple unread groups sorted newest-first within above section | Multi-group sort |

### 8.3 loadOrbitGroups (Orbit)
**File:** `test/features/orbit/application/load_orbit_groups_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `loadOrbitGroups` | returns empty list when no groups | Empty state |
| | loads active groups only (excludes archived) | Archive filter |
| | includes latest message preview | Preview loading |
| | includes unread count | Unread count |
| | sorts by most recent activity first | Activity sort |
| | uses createdAt as fallback when no messages | Fallback sort |
| | returns null latestMessage when group has no messages | Null preview |
| | loads a single group snapshot by group id | Single lookup |
| | returns null when a group snapshot no longer exists | Missing group |

### 8.4 Orbit Archived Groups (group-relevant subset)
**File:** `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `OrbitScreen archived groups` | shows archived groups in archived tab even when no archived friends | Archived visibility |
| | shows empty state when no archived friends and no groups | Empty state |
| | shows groups in all tab | All-tab rendering |

### 8.5 GroupRow BiDi (Orbit)
**File:** `test/features/orbit/presentation/widgets/group_row_bidi_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `GroupRow` | renders LTR sender plus Arabic-first body with RTL body direction | BiDi preview |
| | renders Arabic sender plus English-first body with LTR body direction | BiDi preview |
| | renders empty preview fallback when no structured message | Empty preview |
| | renders mixed-script preview content | Mixed script |
| | renders announcement groups without throwing | Announcement compat |

### 8.6 Swipeable Group Row (Orbit)
**File:** `test/features/orbit/presentation/widgets/swipeable_group_row_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Swipeable Group Row` | swiping left reveals only Delete + Archive (no Block) | Swipe actions |
| | tapping Archive fires onArchive callback | Archive callback |
| | tapping Delete fires onDelete callback | Delete callback |
| | archived group shows Unarchive on swipe | Unarchive action |

### 8.7 Push Open Flow (group-relevant subset)
**File:** `test/features/push/application/chat_and_group_push_open_flow_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `chat and group push open flow` | background group push opens group only after targeted group catch-up | Background push sequencing |
| | terminated group push opens group only after targeted group catch-up | Terminated push sequencing |

### 8.8 resolveGroupNotificationRouteTarget
**File:** `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `resolveGroupNotificationRouteTarget` | returns the existing group without draining inbox | Existing group |
| | returns the existing pending invite without draining inbox | Existing invite |
| | drains inbox and resolves a newly stored pending invite | Inbox drain + invite |
| | drains inbox and resolves a newly materialized group | Inbox drain + group |
| | returns missing when neither group nor invite can be recovered | Missing guard |
| | returns missing for a stale removed-group notification after local cleanup | Removed-group stale notification denial |

### 8.9 Group Notification Dedup
**File:** `test/integration/group_notification_dedupe_integration_test.dart`

| Test | What it covers |
|------|----------------|
| background push announcement suppresses later local group notification for the same message | Notification dedup |

### 8.10 Intro Group Header
**File:** `test/features/introduction/presentation/widgets/intro_group_header_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `IntroGroupHeader` | renders mixed-script introducer usernames | Unicode rendering |
| | renders plain English usernames | Basic rendering |
| | dynamic Arabic-first username stays explicit inside header | RTL text |
| | dynamic English-first username stays explicit inside header | LTR text |

### 8.11 loadFeed with Group Messages (Feed)
**File:** `test/features/feed/application/load_feed_use_case_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `loadFeed with group messages` | returns group thread items when group repos provided | Group thread loading |
| | group items merge with contact items sorted by timestamp | Merge + sort |
| | dissolved groups stay visible but project frozen feed affordances | Dissolved feed visibility + frozen affordances |
| | no group items when group repos not provided | Feature gate |
| | archived groups excluded from feed | Archive filter |
| | groups with no messages produce no thread items | Empty group |
| | loadGroupFeedItems batch-loads media attachments | Media batch loading |
| | loadFeed includes group media attachments | Media inclusion |

### 8.12 Feed Projection Parity (group-relevant subset)
**File:** `test/features/feed/application/feed_projection_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `feed projection parity` | group message upsert and reorder matches cold load | Incremental upsert + frozen-state parity |
| | group message with media flows through to ThreadMessage | Media propagation |
| | archived group removal matches cold load | Archive removal |
| | loadGroupFeedSnapshot includes media attachments | Snapshot media |
| | loadGroupFeedSnapshot without media repos returns empty media | Null media repo |

### 8.13 FeedStore (group-relevant subset)
**File:** `test/features/feed/application/feed_store_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `FeedStore` | replaceGroupSnapshot updates one keyed group while preserving contact threads | Snapshot replace |

### 8.14 FeedItem GroupThreadFeedItem (Feed)
**File:** `test/features/feed/domain/models/feed_item_test.dart`

| Test | What it covers |
|------|----------------|
| ThreadFeedItem.isGroup returns false | Group discrimination |
| GroupThreadFeedItem.isGroup returns true | Group discrimination |
| GroupThreadFeedItem provides all CardThreadFeedItem getters | Interface |
| has type groupThread | Type identity |
| stores group type correctly for all types | Type mapping |
| active announcement readers stay read-only for compose but can still react | Announcement affordance split |
| dissolved groups disable both write and react affordances | Dissolved affordance freeze |

### 8.15 OpenModeCardBody (Feed group subset)
**File:** `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`

| Test | What it covers |
|------|----------------|
| group header uses RTL for Arabic-first mixed display name | BiDi rendering |
| renders group avatar and group name for GroupThreadFeedItem | Group avatar |
| group message with media passes media to MessageBubble in open mode | Media propagation |
| group thread: tapping group avatar fires onViewEarlier | Avatar navigation |

### 8.16 FeedCard (Feed group subset)
**File:** `test/features/feed/presentation/widgets/feed_card_test.dart`

| Test | What it covers |
|------|----------------|
| renders OpenModeCardBody for unread GroupThreadFeedItem | Open mode |
| renders CollapsedModeCardBody for read GroupThreadFeedItem | Collapsed mode |
| session reply forces CollapsedModeCardBody for unread group card | Session reply |
| active group card without session reply stays in open mode | Mode persistence |

### 8.17 CollapsedModeCardBody (Feed group subset)
**File:** `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`

| Test | What it covers |
|------|----------------|
| renders group avatar for GroupThreadFeedItem | Group avatar |
| preview label uses per-message senderUsername for group | Sender label |
| group card shows thumbnail when message has downloaded image | Image thumbnail |
| group card shows icon fallback when media not yet downloaded | Download fallback |
| group card media-only message shows thumbnail + Photo label | Photo label |
| group card media-only GIF message shows thumbnail + GIF label | GIF label |
| group thread collapsed: tapping avatar navigates | Avatar navigation |

### 8.17a FeedScreen (Feed group subset)
**File:** `test/features/feed/presentation/screens/feed_screen_test.dart`

| Test | What it covers |
|------|----------------|
| inline group reaction chips route through the dedicated inspection callback | Inline discussion reaction inspection |
| announcement reader cards keep inline reaction inspection available while compose stays read-only | Inline announcement-reader parity |
| dissolved group cards show dissolved copy and hide reply and reaction entry | Dissolved inline frozen-state |

### 8.18 FeedWired (Feed group subset)
**File:** `test/features/feed/presentation/screens/feed_wired_test.dart`

| Test | What it covers |
|------|----------------|
| loads the Orbit badge from pending group invites on first load | Invite badge init |
| refreshes the Orbit badge when a pending group invite arrives | Invite badge stream |
| inline orbit return refreshes the Orbit badge after local pending group invite changes | Invite badge refresh |
| collapse from open-mode group card marks messages read and collapses | Read marking |
| displays group thread cards when group data exists | Group card rendering |
| refreshes feed on incoming group message | Message stream |
| incremental group message carries media attachments to feed card | Media propagation |
| incoming group message clears session reply so card shows open mode | Session reply clear |
| incoming group message updates only the affected group thread | Incremental update |
| orbit route result refreshes only the changed group snapshot | Snapshot refresh |
| changed group snapshot refresh updates the feed group avatar metadata | Avatar metadata |
| group card + button shows media picker bottom sheet | Media picker |
| group swipe-to-reply shows preview and persists quotedMessageId on send | Swipe to quote |
| group inline send wraps publish in a background task | Background task |
| group inline send becomes retry-discoverable before publish resolves | Retry discovery |
| group inline reply shows session reply immediately before network completes | Session reply |
| group inline reply restores quote and draft on send failure | Failure recovery |
| group inline reply shows session reply on success end-to-end | Session reply E2E |
| group inline reply treats zero-peer publish as success and keeps the message sent | Zero-peer send |
| incremental group updates preserve quoted replies in feed cards | Quote preservation |
| feed opens announcement admins with a writable group conversation | Announcement write |
| feed entry keeps group long-press actions aligned with the shared conversation surface | Feed long-press parity |
| feed entry keeps group reaction inspection aligned with the shared conversation surface | Feed reaction-inspection parity |
| stale dissolved feed reaction entry restores prior state and refreshes the card | Dissolve race recovery |

### 8.19 OrbitWired (Orbit group subset)
**File:** `test/features/orbit/presentation/screens/orbit_wired_test.dart`

| Test | What it covers |
|------|----------------|
| tapping FAB opens menu with New Group and New Announce | Create menu |
| displays group rows when groups exist | Group rendering |
| displays structured group rows with latest message preview | Preview rendering |
| refreshes only the affected group on incoming group message | Incremental refresh |
| create-group route result refreshes only the affected group | Create refresh |
| interleaves groups and friends sorted by last activity | Activity sort |
| pending group invites are visible from the Intros tab and counted in the Orbit badge | Invite badge |
| accepting a pending group invite from Intros joins the group | Invite accept |
| all tab renders active groups before archived hydration completes | Archived hydration |
| orbit entry keeps group long-press actions aligned with the shared conversation surface | Orbit long-press parity |
| orbit entry keeps group reaction inspection aligned with the shared conversation surface | Orbit reaction-inspection parity |

### 8.20 Notification Body for Group Messages (Push)
**File:** `test/features/push/application/notification_body_for_message_test.dart`

| Test | What it covers |
|------|----------------|
| group image-only message body is "Alice: Photo" | Image body |
| group GIF-only message body is "Alice: GIF" | GIF body |
| group audio-only message body is "Alice: Voice message" | Voice body |
| group captioned image body is "Alice: Check this out" | Caption body |

### 8.21 Background Push Notification Fallback (Push group subset)
**File:** `test/features/push/application/background_push_notification_fallback_test.dart`

| Test | What it covers |
|------|----------------|
| shows fallback for group_message type with groupId | Group fallback |
| shows group fallback on iOS when Flutter sees only the data payload | iOS data payload |
| skips group fallback on iOS when RemoteMessage already has a visible notification payload | iOS visible guard |
| skips fallback for group_message type without groupId | Missing ID guard |
| shows fallback for group_invite type and routes to intros | Invite fallback |

### 8.22 Notification Tap Smoke (group subset)
**File:** `test/integration/notification_tap_smoke_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `remote push tap (warm app)` | group_invite → intros | Warm invite tap |
| | group_message → group | Warm message tap |
| `remote push tap (terminated app)` | group_invite → intros | Terminated invite tap |
| | group_message → group | Terminated message tap |
| `local notification tap (warm app)` | group payload | Local group tap |
| `local notification initial launch` | group initial launch | Cold group launch |
| `background push fallback → show → tap → route` | group_invite push → fallback → tap → intros route | Invite fallback route |
| | group_message push → fallback → tap → group route | Message fallback route |
| `edge cases` | group_message without groupId → missing | Missing ID edge case |
| | group: with empty groupId → nothing fires | Empty ID edge case |
| `drain correctness per notification kind` | conversation drains 1:1 inbox, not group | 1:1 drain isolation |
| | contactRequest drains 1:1 inbox, not group | 1:1 drain isolation |
| | intros drains 1:1 inbox, not group | 1:1 drain isolation |
| | group_invite drains 1:1 inbox, not group | Invite drain isolation |
| | group drains targeted group inbox, not 1:1 | Group drain targeting |

### 8.23 Loading States Smoke (group subset)
**File:** `test/features/loading_states_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| Group list loading renders without overflow | Group list loading |

### 8.24 Network Failover (group-relevant subset)
**File:** `test/core/resilience/network_failover_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `Phase 7 — Network failover: group send path` | group send path survives relay A loss | Group relay failover |
| `Phase 7 — Network failover: runtime recovery flags` | runtime feature flags can disable new recovery behaviors intentionally | Recovery feature gate |

### 8.25 Pending Message Retrier Upload Ordering (group-relevant subset)
**File:** `test/core/services/pending_message_retrier_upload_ordering_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `PendingMessageRetrier -- retryIncompleteUploads ordering` | online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry | Recovery step ordering |

### 8.26 Share to Contact Smoke (group-relevant subset)
**File:** `test/features/share/integration/share_to_contact_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| 6a: share text can target multiple selected recipients from the picker | Multi-target share including group |
| 6i: announcement group where user is not admin is excluded from picker | Announcement write-guard in picker |

### 8.27 Share Batch Delivery Coordinator (group-relevant subset)
**File:** `test/features/share/application/share_batch_delivery_coordinator_test.dart`

| Test | What it covers |
|------|----------------|
| text-only group share wraps publish in a background task and stays sent on durable success | Group share bg task |
| group share keeps live-peer pending rows queued until inbox custody closes | Group share inbox custody |

### 8.28 Share Target Picker Wired (group-relevant subset)
**File:** `test/features/share/presentation/share_target_picker_wired_test.dart`

| Test | What it covers |
|------|----------------|
| 2j, 2q, 2r, 2s: loads only active contacts and writable groups | Group filtering in picker |
| send invokes the coordinator exactly once with selected targets | Multi-target group send |
| partial failure keeps only failed targets selected | Group share partial failure |

### 8.29 PendingMessageRetrier (group-relevant subset)
**File:** `test/core/services/pending_message_retrier_test.dart`

| Test | What it covers |
|------|----------------|
| group continuity sweep runs on a shorter cadence than full retry loop | Group sweep cadence |
| needsGroupRecovery false-to-true while online triggers immediate continuity sweep | Recovery trigger |
| immediate group recovery does not reset the 30-second fallback timer | Timer independence |
| successful retrier-owned nodeRequestedRecovery sends ack on immediate recovery | Recovery ack |
| successful retrier-owned recovery sends ack on the retry sweep path | Sweep ack |
| failed retrier-owned recovery does not send ack | Failed recovery guard |

### 8.30 NotificationRouteTarget (group-relevant subset)
**File:** `test/core/notifications/notification_route_target_test.dart`

| Test | What it covers |
|------|----------------|
| fromRemoteMessageData maps group_message to group route | Group route mapping |
| fromRemoteMessageData maps group_invite to intros route | Invite route mapping |
| group payload round-trips through toPayload and fromPayload | Payload round-trip |

### 8.31 NotificationPushTapNavigate (group-relevant subset)
**File:** `test/core/notifications/notification_push_tap_navigate_test.dart`

| Test | What it covers |
|------|----------------|
| group push navigates to group | Group push navigation |

### 8.32 ShareTargetPickerScreen (group-relevant subset)
**File:** `test/features/share/presentation/share_target_picker_screen_test.dart`

| Test | What it covers |
|------|----------------|
| 2c and 2d: renders contact and group sections | Group section rendering |
| tapping group toggles selection via callback | Group toggle |
| 2g: search filters both contacts and groups | Group search |
| 2i: empty contacts/groups shows empty state | Empty group state |

### 8.33 Routing Smoke Group Criteria
**File:** `test/integration/routing_smoke_group_criteria_test.dart`

Added for Report 85. These host-side criteria guard the paired simulator
orchestrator from passing on sender-only or pending receiver evidence.

| Group | Test | What it covers |
|-------|------|----------------|
| `routing smoke group criteria` | G2 requires all five warm messages | Warm-burst receive count |
| | G4 requires Bob receiver-visible inbox recovery | Offline inbox recovery evidence |
| | G5 rejects pending or missing receiver timeline evidence | Full-lifecycle receiver timeline completeness |
| | G7 requires rotation plus pre and post rotation receipts | Rotation traffic receive proof |
| | G8 requires Bob receipt in addition to Alice publish success | Flood-publish receiver proof |

### 8.34 Group Multi Party Device Criteria (selected row-owned additions)
**File:** `test/integration/group_multi_party_device_criteria_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `group multi party device criteria` | accepts valid DE-017 membership-ordering verdicts | Validates DE-017 live membership-ordering proof fields |
| | rejects DE-017 without membership-ordering proof | Fails missing membership-ordering evidence |
| | rejects DE-017 repaired post-removal leak | Fails post-removal plaintext leakage after membership repair |
| | accepts valid IR-001 offline active reconnect verdicts | Validates Bob missed-message drain, exactly-once replay, and post-drain live delivery proof fields |
| | rejects IR-001 without offline reconnect proof | Fails missing offline reconnect evidence |
| | rejects IR-001 missed backlog count mismatch | Fails missed backlog count/key mismatch |
| | rejects IR-001 post-drain live delivery without live proof | Fails a post-drain message that is not proven live |
| | accepts private_offline_remove ML-006 and IR-004 proof verdicts | Positive live criteria validates offline removal plus IR-004 post-removal replay proof fields |
| | rejects private_offline_remove without IR-004 proof fields | Fails missing Charlie IR-004 post-removal replay proof evidence |
| | rejects IR-004 proof when Charlie receives post-removal plaintext | Fails removed-member post-removal plaintext leakage in IR-004 proof |
| | accepts valid GM-007, KE-018, and IR-005 history-boundary verdicts | Positive live criteria validates GM-007 membership churn plus KE-018/IR-005 replay-window proof fields |
| | rejects GM-007 without IR-005 re-add replay proof | Fails missing IR-005 re-add replay evidence |
| | rejects IR-005 proof with Charlie removed-window replay | Fails removed-window plaintext leakage in IR-005 proof |
| | accepts valid IR-015 variant replay verdicts | Validates Alice live send proof, Bob offline replay drain proof, Charlie live receipt proof, exact variant counts, quote target, and media descriptor rehydration |
| | rejects IR-015 without media rehydration proof | Fails missing or false `ir015VariantReplayProof.mediaVariantsRehydrated` evidence |
| | rejects IR-015 quote target mismatch | Fails quote replay proof when the quote does not reference the text variant message |
| | IR-016 accepts long-offline retention cutoff proof verdicts | Validates explicit expired/retained cutoff proof fields, Bob retained backlog visibility, Charlie live-control receipt, and no expired-message resurrection |
| | IR-016 rejects silent-complete Bob retention proof | Fails Bob proof that claims a complete drain while omitting the explicit incomplete-history retention cutoff state |
| | IR-016 rejects Bob expired-message resurrection | Fails Bob proof that surfaces expired backlog messages after the retention cutoff |

---

## 9. Test Helpers & Fakes

The group test infrastructure includes the following shared fakes:

| File | Purpose |
|------|---------|
| `test/shared/fakes/fake_group_pubsub_network.dart` | Simulates GossipSub pubsub network with topic-based fan-out, deterministic seeded fault injection, injectable delivery-delay scheduling, delivery delays, and drop rates |
| `test/shared/fakes/fake_group_pubsub_network_test.dart` | GO-012 fake-network determinism proof: seeded drops/delays repeat and `resetCounters()` restores the seeded drop sequence |
| `test/shared/fakes/group_test_user.dart` | Encapsulates full per-user group stack (listener, bridge, repos) for multi-user integration tests |
| `test/shared/fakes/in_memory_group_repository.dart` | In-memory group repository for fast tests |
| `test/shared/fakes/in_memory_group_message_repository.dart` | In-memory group message repository for fast tests |
| `test/shared/fakes/in_memory_pending_group_invite_repository.dart` | In-memory pending invite repository for fast tests |

---

## 10. Coverage Gaps

Areas of the group chat feature that have **no dedicated test coverage** or only indirect coverage:

### 10.1 Data Layer
- **Group message full-text search**: No tests for any search/query by content.

### 10.2 Application Layer
- **GroupMessageListener**: Has broad coverage for system messages, notifications, reactions, media forwarding, and DB-002 event-log replay/tamper protection. System message handler coverage includes member_added, member_removed, members_added, group_dissolved, member_role_updated, group_metadata_updated, and key_rotated.
- **Flow-event contract inventory**: No dedicated tests pin group-specific event family names or validate their structured payloads.
- **Concurrent key rotation during member removal**: Only tested through the member_removal_integration_test; no isolated concurrency stress test.

### 10.3 Presentation Layer
- **GroupConversationWired background task AN-008 coverage**: `group_conversation_wired_bg_task_test.dart` keeps all 15 background-task tests active, including the former 5 skipped bg:begin/bg:end lifecycle, upload cleanup, announcement media metadata, and order-recording bridge rows. Direct suite and adjacent announcement media gates passed; no AN-008 skipped rows remain.

### 10.4 Integration / E2E
- **True multi-device E2E**: Multi-device tests use in-memory fakes in the repo-owned suite. OS-010 evidence on 2026-04-30 revalidated `group_multi_device_convergence_test.dart` as the host oracle, extended `group_multi_device_policy_test.dart` so composer drafts are explicitly device-local, and found `FLUTTER_DEVICE_ID` plus `MKNOON_RELAY_ADDRESSES` unset. Earlier 2026-04-12 spare iOS proof remains in `/tmp/md004_group_multi_device_real_rerun8_20260412.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`; a fresh same-account two-device run covering messages, read state, keys, drafts, and membership remains device-lab evidence.
- **Push notification trigger path**: Group push routing is tested. Earlier 2026-04-12 spare iOS proof remains in `/tmp/ux009_notification_open_ui_smoke_20260412_rerun16e_drive.log`, and the final 2026-04-12 deployed-relay rerun on the primary iOS pair is recorded in `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`.
- **Network partition healing**: Report 85 tightened `temporary partition replays missed backlog` in `group_resume_recovery_test.dart` to three missed split-window messages across cursor-ordered durable inbox pages plus post-heal live delivery. A real bridge/GossipSub partition-heal simulator proof remains device-lab residual evidence.
- **Full simulator media and recovery matrix**: Report 85 added host/app-layer media onboarding, media fan-out, retry, foreground-drain, and strict paired-run criteria coverage. MD-014 targeted recheck on 2026-04-30 used configured `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` plus supplied relay addresses and `group-real-network-nightly` passed. GMAR-004 later made the configured `integration_test/group_new_member_media_simulator_proof_test.dart` proof green by fixing stale video/voice fixture metadata under group media integrity policy, and added host reopen/retry/offline duplicate proof. GMAR-005 closed Report 90's all-recipient media/gate-confidence layer on 2026-05-03 by passing configured simulator media proofs, `media_message_journey_e2e_test.dart`, `media_stable_id_smoke_test.dart`, the paired simulator routing/group and foreground group push smoke commands with relay addresses, the device-pinned `all` gate, completeness check, broad `flutter test`, Go module tests, and `git diff --check`. Full announcement-specific simulator media journeys, OS-state group notification matrix breadth, relay outage replay and duplicate-prevention breadth, broader failure/recovery UI breadth, and the file dimension while MD-013 is unsupported still require configured device-lab runs or an explicit scope decision.

### 10.5 Security
- **Replay attack on group messages**: Now covered by `handle_incoming_group_message_use_case_test.dart` and `group_resume_recovery_test.dart`, which pin timestamp-tampered replay dedup plus remove/dissolve cutoff enforcement on the Flutter-visible receive path.
- **Tampered group message payload**: Now covered by `pubsub_decryption_failure_test.go`, which pins wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload rejection without any `group_message:received` event, and `go_bridge_client_test.dart`, which keeps the owned Flutter diagnostics route pinned.
- **Real-crypto onboarding and re-add**: Now covered at the real Go-bridge app boundary by `integration_test/group_real_crypto_onboarding_test.dart`. Live GossipSub two-node delivery remains separate device-lab evidence.
- **Membership-event signature forgery**: Now covered at the Go envelope-validator layer by `TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature` in `pubsub_test.go`; app-layer authorization remains covered by `group_message_listener_test.dart`.
- **Key rotation race conditions**: MS-018 now has direct app-layer proof in `send_group_message_use_case_test.dart`, `group_key_update_listener_test.dart`, and `drain_group_offline_inbox_use_case_test.dart` for send-time epoch snapshots, before/during/after local rotation commit sends, pending receive-side key update sends, mixed old/new encrypted replay, and safe future-epoch undecryptable placeholder creation without wrong-epoch decrypt or plaintext fallback. GEK-001 adds direct listener/Go-boundary proof that delayed older direct key updates and same-generation conflicting material cannot promote or replace accepted active key state. GEK-002 adds host app-layer proof that live decrypt failure plus durable replay plus later key arrival converges to one repaired visible row, and its old fixed-date receipt-fixture follow-up is now clock-controlled. GEK-003 adds host app-layer proof for the combined partial key-update delivery plus immediate post-rotation send race, including durable replay canonical identity and later stale-recipient repair. GEK-004 adds host app-layer proof that delayed membership/config catch-up lets a newly accepted sender's durable `unknown_sender` replay recover exactly once before cursor commit. GEK-005 ran final host/Go/gate/device reconciliation; the final program verdict is `residual_only` because the remaining limitation is exact live three-party GEK split-delivery proof scope, not a repo-owned host/Go/gate blocker.
- **Group observability contract drift**: Now covered by `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `retry_failed_group_inbox_stores_use_case_test.dart`, which pin stable begin/success/skip/error/timing flow-event names and required detail keys on the shipped Flutter-owned group send/recovery/retry paths.

### 10.6 Go / Dart Boundary
- **Create-time description remains intentionally unsupported**: Go `GroupCreate()` still does not parse `description`, and the shipped create surface does not expose it. Any future scope change will need new Go/Dart round-trip proof.

---

## 11. E2E / Device Tests

Tests in `integration_test/` that run on a real device or simulator via `flutter test integration_test/`.

Primary simulator / emulator targets for the remaining exploratory/device-proof rows:
- Android primary pair: `emulator-5554`, `emulator-5556`
- iOS primary pair: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`), `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`)
- iOS spare validation: `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`)

### 11.1 Group Recovery E2E
**File:** `integration_test/group_recovery_e2e_test.dart`

| Test | What it covers |
|------|----------------|
| group member receives missed group messages after resume drain | Resume drain delivery |
| announcement reader receives missed announcement after resume drain | Announcement resume drain |
| group inbox drain deduplicates message already received live | Cross-path dedup |
| offline recovered dissolved group exposes local-only cleanup on Group Info | Device-backed dissolved cleanup |
| watchdog restart rejoins topics and multi-group drain stays bounded | Watchdog batch recovery |

### 11.2 Group Recovery CLI E2E
**File:** `integration_test/group_recovery_cli_e2e_test.dart`

| Test | What it covers |
|------|----------------|
| real CLI peer drives live and inbox group recovery | CLI-driven recovery round-trip |

### 11.3 Real-Crypto Group Onboarding
**File:** `integration_test/group_real_crypto_onboarding_test.dart`

Added for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `real-crypto group onboarding` | Bob accepts a real encrypted invite, decrypts first-add and re-add group ciphertext | Real Go-bridge ML-KEM invite acceptance, group AES-GCM decrypt, re-add current epoch decrypt, retained old-key decrypt failure |

### 11.4 Foreground Group Push Drain
**File:** `integration_test/foreground_group_push_drain_test.dart`

Extended for Report 85.

| Group | Test | What it covers |
|-------|------|----------------|
| `foreground group push drain` | foreground group push drains the targeted group inbox and surfaces one in-app notification | Targeted group inbox drain and in-app notification |
| | foreground group push drains media exactly once with descriptor and download trigger | Representative image media drain, descriptor preservation, one download trigger |
| | foreground group push does not duplicate a message or notification already received live | Live-plus-push dedupe |
| | foreground 1:1 push still drains the 1:1 inbox only | Cross-kind isolation |
| | foreground post push does not trigger any drain | Unsupported-kind guard |

### 11.5 Multi-Relay Failover
**File:** `integration_test/multi_relay_failover_test.dart`

Tightened for Report 85.

| Mode | Test | What it covers |
|------|------|----------------|
| Strict fixture guard | multi-relay fixture is required for this closure run | Fails clearly when `MKNOON_REQUIRE_MULTI_RELAY=true` and fewer than two relay addresses are configured |
| No fixture | two relay failover keeps 1:1 delivery working (requires `MKNOON_RELAY_ADDRESSES`) | Truthful skip placeholder, not closure evidence |
| No fixture | two relay failover keeps group recovery working (requires `MKNOON_RELAY_ADDRESSES`) | Truthful skip placeholder, not closure evidence |
| Configured fixture | imports `transport_e2e.main()` and `group_recovery_e2e.main()` | Real-stack 1:1 and group recovery under multi-relay configuration |

### 11.6 Group New-Member Media Simulator Proof
**File:** `integration_test/group_new_member_media_simulator_proof_test.dart`

| Test | What it covers |
|------|----------------|
| group new-member media simulator proof | GMAR-004 configured simulator proof for visible incoming/outgoing text-plus-video/voice rows, `VideoThumbnailOverlay`, `AudioPlayerWidget`, voice play/pause, video open, and conversation-surface reopen preservation on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` |

**Recurring command:** `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly`

---

## 12. Go-Side Tests

Group-related tests in `go-mknoon/`. Counts reflect only `func Test*` functions that exercise group messaging paths; files with mixed group/non-group tests show only the group-relevant subset.

### 12.1 Group Crypto
**File:** `go-mknoon/crypto/group_test.go` (14 tests)

| Test | What it covers |
|------|----------------|
| TestGenerateGroupKey_Length | Key is 32 bytes |
| TestGenerateGroupKey_Unique | Two keys differ |
| TestGroupEncryptDecrypt_RoundTrip | Encrypt/decrypt fidelity |
| TestGroupEncryptDecrypt_WrongKey | Wrong-key rejection |
| TestGroupEncryptDecrypt_TamperedCiphertext | Tampered ciphertext detection |
| TestGroupEncryptDecrypt_TamperedNonce | Tampered nonce detection |
| TestGroupEncryptDecrypt_UniqueNonces | Unique nonce per encrypt |
| TestGroupEncryptDecrypt_EmptyString | Empty plaintext |
| TestGroupEncryptDecrypt_LargeMessage | 1 MB message |
| TestEncryptGroupMessage_InvalidKey | Non-base64 key rejection |
| TestEncryptGroupMessage_WrongKeyLength | 16-byte key rejection |
| TestDecryptGroupMessage_InvalidBase64 | Base64 error handling |
| TestBuildGroupSignatureData_Format | Pipe-delimited signature format |
| TestBuildGroupSignatureData_Deterministic | Deterministic signature |

### 12.2 Group Envelope / Wire Format
**File:** `go-mknoon/internal/group_envelope_test.go` (11 tests)

| Test | What it covers |
|------|----------------|
| TestMarshalParseGroupEnvelope_RoundTrip | v3 envelope round-trip |
| TestParseGroupEnvelope_InvalidJSON | Malformed JSON rejection |
| TestParseGroupEnvelope_MissingFields | Required field validation |
| TestIsGroupEnvelope_V3GroupMessage | v3 detection |
| TestIsGroupEnvelope_V1Message | v1 rejection |
| TestIsGroupEnvelope_V2Message | v2 rejection |
| TestIsGroupEnvelope_InvalidJSON | Invalid JSON handling |
| TestMarshalParseGroupPayload_RoundTrip | Payload round-trip |
| TestMarshalParseGroupPayload_WithExtra | Extra field preservation |
| TestGroupMessagePayloadWithMediaExtra | Media metadata in payload |
| TestGroupMessagePayloadWithQuotedMessageIdExtra | Quoted reply support |

### 12.3 PubSub Core
**Files:** `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` (96 listed lifecycle/core tests)

Covers topic creation, validator logic, config updates, discovery, and publish operations:

| Category | Key Tests |
|----------|-----------|
| Topic & Config | TestGroupTopicName, TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata, TestJoinGroupTopic_LogOmitsHumanReadableMetadata, TestGroupConfig_Serialization, TestGroupKeyInfo_Serialization, TestGroupMember_Serialization, TestGroupMember_OmitEmpty |
| Writer Authorization | TestIsAllowedWriter_ChatAnyMember, _AnnouncementAdminOnly, _AnnouncementMemberBlocked, _QAAnyMember, _NonMember |
| Member Lookup | TestFindMember_Found, _NotFound, _DuplicatePeerId_ReturnsFirst |
| Validator | TestGroupTopicValidator_ValidMessage, _TransportPeerIdMatchesEnvelopeSender, _RejectsTransportPeerIdMismatch, _InvalidJSON, _UnknownGroup, _UnauthorizedSender, _RejectsUnauthorizedEventFamiliesBeforeForward, _AnnouncementNonAdminRejected, _BadSignature, _SpoofedPublicKey, _RejectsForgedMembershipSystemEventSignature, TestGK028ValidateGroupEnvelopeRejectsSenderPublicKeyBypass, _NotV3Envelope, _WrongKeyEpoch, _EmptyMembersList, _ConcurrentValidation |
| Join / Leave | TestJoinGroupTopic_WithMultiMemberConfig, _ValidatorAcceptsAllListedMembers, _FailsWithoutPubSub, _RejectsDoubleJoin, TestLeaveGroupTopic_CancelsDiscoveryContext, TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish, TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState |
| Subscription Lifecycle | TestGP024SubscriptionErrorLogsOnlyRealFailures, TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines |
| Config Update | TestUpdateGroupConfig_ReplacesConfigAtomically, _NonExistentGroup, _PreservesDiscoveryLoop, _ConcurrentUpdates |
| Invite Lifecycle | TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember, _AnnouncementGroup_NewWriterCannotPublish |
| Discovery | TestGroupRendezvousNamespace, _MatchesTopicName, _EmptyGroupId, TestFilterDiscoveredPeers_*, TestFilterDiscoveredGroupMembers_*, TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember, TestGO006DiscoveryEventsExposeMissingPeerCondition, TestGroupDiscoveryInterval, _WarmInterval, TestGroupDiscoveryConcurrency, TestGroupRecoveryLimiter_*, TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup, TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext, TestGroupDiscoveryLoop_BacksOff*, _DedupesConcurrentPeerDials, TestGP017InFlightDialGateBlocksOnlyWhileActive, TestGP018WarmRetryCadenceKeepsActiveGroupResponsive, TestGP019DiscoveryBackoffResetsAfterPartialProgress, TestGP020AllExpectedConnectedReturnsToMaintenanceCadence, TestGroupDiscoveryCycle_NoKnownPeersUsesRendezvousFallback |
| Recovery | TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh |
| Publish | TestPublishGroupMessage_BuildsCorrectEnvelope, TestBuildGroupMessageExtra_PreservesQuotedMessageId, TestGK031BuildGroupMessageExtraExplicitMessageIDWins, TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId |
| Encrypt / Relay Visibility | TestGroupMessage_EncryptDecryptRoundTrip, TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay, TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay |
| Diagnostics | TestAnnouncementGroup_AdminPublishWithZeroPeersStillUsesDurableFallback, TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend, TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons, TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport |
| Peer Preference | TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback, TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay, TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs |
| Key Lookup | TestGetGroupKeyInfo_ReturnsCurrentKey, TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState, _ReturnsNilForUnknownGroup |
| Node Lifecycle | TestStopNode_CancelsAllDiscoveryContexts, TestGroupDiscoveryCtx_InitializedByInitPubSub, TestCountConnectedGroupMembers_UnknownGroup |

### 12.4 PubSub Delivery
**File:** `go-mknoon/node/pubsub_delivery_test.go` (15 tests)

| Test | What it covers |
|------|----------------|
| TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers | Zero-peer count |
| TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected | Positive peer count |
| TestGP007ZeroPeerPublishUsesBoundedSettleWait | Zero-peer publish preflight uses bounded settle wait and reports durable fallback peer count |
| TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer | Host-connected expected peer that has not joined the topic stays absent from live topic metrics and publish diagnostics report zero topic peers plus one missing expected peer |
| TestGA018SameTransportSelfEchoIsSkippedOnce | Same-transport local echo is skipped while local publish debug remains separate |
| TestGK031PublishGroupMessageExplicitMessageIDWinsOverOptsMessageID | Explicit messageId wins over conflicting opts.messageId in live publish/receive path |
| TestGK032PublishedAtNanoInvalidValuesStillEmitMessageWithoutDeliveryMs | Missing, malformed, overflow-sized, and non-string publishedAtNano values still emit live encrypted receive events without deliveryMs |
| TestPublishGroupMessage_RefreshesMissingKnownTopicPeersBeforePublish | Peer refresh before publish |
| TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup | Unjoined group error |
| TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt | Duplicate live PubSub publishes preserve the same application messageId after decrypt |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait | Pre-circuit member dial |
| TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown | Direct address preference |
| TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady | Relay-readiness ordering for pre-relay direct recovery and post-readiness register/discover |
| TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow | Warm window retry |
| TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery | Warm retry timing |

### 12.5 Key Rotation Grace Period
**File:** `go-mknoon/node/pubsub_key_rotation_grace_test.go` (9 tests)

| Test | What it covers |
|------|----------------|
| TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace | Old key during grace |
| TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires | Old key after grace |
| TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace | Current key during grace |
| TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace | Removed sender cannot use previous-epoch grace |
| TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery | Unknown future epoch rejects before delivery |
| TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline | Grace state preservation |
| TestJoinGroupTopic_InitialKeyHasNoGraceState | Initial key no grace |
| TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace | Decrypt with old key |
| TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires | Old key after grace stays non-deliverable |

### 12.6 Decryption Failure Events
**File:** `go-mknoon/node/pubsub_decryption_failure_test.go` (23 tests; selected entries)

| Test | What it covers |
|------|----------------|
| TestHandleGroupSubscription_EmitsDecryptionFailedEvent | Decryption failure event |
| TestHandleGroupSubscription_EmitsPayloadParseFailedEvent | Parse failure event |
| TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce | Wrong-nonce rejection with no ghost message event |
| TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext | Tampered-ciphertext rejection with no ghost message event |
| TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly | GO-004 wrong-local-key diagnostic metadata without plaintext/key/ciphertext/nonce/signature/private-key leakage |
| TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents | GO-008 decrypt, parse, and validation diagnostics/logs omit plaintext, keys, ciphertext, nonce, signatures, and private keys |
| TestGK028SenderPublicKeyTamperLiveRawPublishRejectsWithoutPayload | GK-028 live raw-publish rejects attacker `SenderPublicKey` bypass without payload or attribution side effects |

### 12.6A Shared Security Proof Harness
**File:** `go-mknoon/node/group_security_harness_test.go` (1 test)

This file also owns the shared raw-envelope mutation, local-node connect/publish,
event wait, and grace-fixture helpers reused by the decryption-failure and
key-rotation suites.

| Test | What it covers |
|------|----------------|
| TestMutateGroupEnvelope_RewritesEncryptedFieldsWithoutChangingRoutingMetadata | Raw envelope mutation helper preserves routing metadata while tampering encrypted fields for later security-row proofs |

### 12.7 Group Inbox
**File:** `go-mknoon/node/group_inbox_test.go` (14 tests)

| Test | What it covers |
|------|----------------|
| TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds | Recipient list marshaling |
| TestBuildGroupInboxStoreRequest_MarshalsPushTitle | Push title |
| TestBuildGroupInboxStoreRequest_MarshalsPushBody | Push body |
| TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope | Opaque encrypted replay envelope stays in the relay request message field without plaintext body, media key, invite token, or history text when notification preview text is safe |
| TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero | Default limit |
| TestGroupInboxRetrieveCursor_StableAcrossPages | Cursor stability |
| TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation | No duplicate on continue |
| TestGroupInboxRetrieveCursor_RequiresStartedNode | Node startup guard |
| TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50 | Negative limit default |
| TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream | Failed GroupInboxStore relay stream resets; successful retry stream closes cleanly |
| TestIR003GroupInboxRetrieveUsesInclusiveSinceBoundary | Legacy timestamp retrieve requests boundary minus one millisecond and returns boundary plus adjacent messages |
| TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor | Non-positive cursor retrieve limits serialize as 50 and preserve caller cursors |
| TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50 | Non-positive repair-range limits normalize to 50 without changing non-limit fields |
| TestIR011GroupHistoryRepairRange_NormalizesAndRejectsIdentity | Repair-range identity/source fields trim, default limit applies, and missing group, gap, or source identity rejects before node or relay use |
| TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs | Repair response fills missing group, gap, and source IDs from normalized request values |

### 12.8 Multi-Relay (group and Report 85 relay-recovery subset)
**File:** `go-mknoon/node/multi_relay_test.go` (8 of 22 tests)

| Test | What it covers |
|------|----------------|
| TestNewRelaySelector_GroupsByPeerID | Relay grouping |
| TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails | Direct-to-relay fallback attempt |
| TestRendezvousRegister_TriesSecondRelayWhenFirstFails | Rendezvous register relay fallback |
| TestRendezvousDiscover_TriesSecondRelayWhenFirstFails | Rendezvous discover relay fallback |
| TestInboxStore_TriesSecondRelayWhenFirstFails | 1:1 inbox relay fallback prerequisite |
| TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails | Inbox relay failover |
| TestGroupInboxRetrieveCursor_TriesSecondRelayWhenFirstFails | Cursor relay failover |
| TestMediaUpload_TriesSecondRelayWhenFirstFails | Media relay fallback prerequisite |

### 12.9 Rendezvous
**File:** `go-mknoon/node/rendezvous_test.go` (2 tests)

| Test | What it covers |
|------|----------------|
| TestGroupRendezvousRefresh_KeepsRegistrationAlivePastTTL | TTL refresh |
| TestAnnouncementGroupRendezvousRefresh_UsesSameTTLRefreshPath | Announcement TTL |

### 12.10 Config (group-relevant subset)
**File:** `go-mknoon/node/config_test.go` (1 of 4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupPublishPeerSettleWindows_StayShortForForegroundSend | Peer settle timing |

### 12.10A Protocol Version
**File:** `go-mknoon/node/protocol_version_test.go` (4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupProtocolIDs_AreVersionedCurrentContracts | Current chat, inbox/group inbox, rendezvous, and media protocol IDs remain semver-like `/.../1.0.0` contracts |
| TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly | Current chat protocol opens successfully and an unsupported chat protocol ID is rejected |
| TestSecureLibp2pChannelRequiredBeforeMknoonProtocols | Insecure `libp2p.NoSecurity` host cannot connect to the raw TCP mknoon node address or open `ChatProtocol`, and no insecure peer connection is retained |
| TestGroupProtocolInboxStoreUsesVersionedInboxProtocol | Group inbox store opens relay streams on `InboxProtocol` |

### 12.11 Node / Relay Session / Stream Timeout (group-relevant subset)
**Files:** `go-mknoon/node/node_test.go` (12 of 60 tests), `go-mknoon/node/relay_session_test.go` (5 of 21 tests), `go-mknoon/node/stream_timeout_test.go` (1 of 3 tests)

| Test | File | What it covers |
|------|------|----------------|
| TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure | node_test.go | Public relay refresh before Start returns structured NOT_STARTED failure, reuses host contract, no host/start side effects, and clears the shared recovery gate |
| TestGR002ConcurrentRefreshRelaySessionCallsCoalesce | node_test.go | Concurrent public relay refresh callers share one blocked owner recovery and receive the same coalesced in-place result |
| TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout | relay_session_test.go | Stalled shared recovery waiter times out, clears the gate, and a fresh recovery can start and complete |
| TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState | node_test.go | Stopped-node group recovery acknowledgement returns node not started and preserves pending recovery state without emitting acknowledgement events |
| TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold | relay_session_test.go | Multi-relay watchdog recovery remains false while any reserved relay is below threshold and triggers only once all tracked reserved relays reach the threshold |
| TestGR010RefreshSuccessResetsFailureCounterAndStaleError | relay_session_test.go | Successful refresh resets consecutive failure count, restores reserved/online state, and clears stale relay error from status |
| TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers | node_test.go | Relay connectedness changes update relay-session state only for configured relay peers while non-relay peers create no relay session or relay-state event |
| TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation | relay_session_test.go | Host-reported stale circuit addresses without reservation are detected, filtered from trusted addresses, and not surfaced as healthy/online status |
| TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget | node_test.go | Foreground in-place relay recovery reports configured warm/wait budgets, foreground success attribution, and timing fields within the immediate-success budget path |
| TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe | node_test.go | Relay recovery success and watchdog failure events expose bounded diagnostics while omitting private group content/key fields and sentinel values |
| TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting | node_test.go | Watchdog full-restart preserves original AutoRegister true/false settings and gates personal registration/refresh-loop behavior accordingly |
| TestPersonalRendezvousRefreshLoop_DoesNotStartForGroupNamespaceRegister | node_test.go | Group namespace exclusion |
| TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure | node_test.go | DE-010 native dispatcher recovers one callback panic, logs event/reason evidence, and continues FIFO group-message dispatch without dropped/coalesced residue |
| TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure | node_test.go | DE-011 native dispatcher preserves below-capacity group-message FIFO delivery under pressure while recording near-overflow diagnostics without overflow or drops |
| TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery | node_test.go | DE-012 native dispatcher overflow diagnostics identify a dropped `group_message:received` event with dropped-count and queue-depth evidence for replay recovery |
| TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage | node_test.go | DE-020 native dispatcher delivers a 10,000-character group payload and immediate normal follow-up in FIFO order without coalescing, drops, or residual queue depth |
| TestWatchdog_MarksNeedsGroupRecoveryForFlutter | relay_session_test.go | Watchdog group recovery flag |
| TestOutboundStreams_ApplyDeadlineAcrossChatInboxRendezvousGroupInboxAndMedia | stream_timeout_test.go | Group inbox stream deadline |

### 12.12 Bridge API
**File:** `go-mknoon/bridge/bridge_test.go` (53 of 133 tests)

| Category | Key Tests |
|----------|-----------|
| Crypto | TestGenerateGroupKey_ReturnsKey, TestGroupEncryptDecryptRoundTrip, TestGroupEncryptMessage_InvalidJSON, _MissingFields, TestGroupDecryptMessage_InvalidJSON, _MissingFields, _WrongKey |
| Create | TestGroupCreate_NodeNotInitialized, _InvalidJSON, _MissingFields |
| Join | TestGroupJoinTopic_NodeNotInitialized, _InvalidJSON, _MissingFields, _WithInviteData, _AlreadyJoinedIsIdempotent |
| Leave | TestGroupLeaveTopic_NodeNotInitialized, _InvalidJSON, _MissingGroupId |
| Publish | TestGroupPublish_NodeNotInitialized, _InvalidJSON, _MissingFields, _EmptyTextAndNoMedia_Fails, _MediaOnly_AcceptsEmptyText, _ResponseIncludesTopicPeers, TestBuildGroupPublishOpts_IncludesQuotedMessageId, _EmptyReturnsNil |
| Config Update | TestGroupUpdateConfig_NodeNotInitialized, _InvalidJSON, _MissingGroupId, _WithNewMember |
| Key Rotate | TestGroupRotateKey_NodeNotInitialized, TestRotateKey_InvalidJSON, TestGroupRotateKey_MissingGroupId, _IncrementsEpoch |
| Key Update | TestGroupUpdateKey_NodeNotInitialized, _InvalidJSON, _MissingFields, _UpdatesStoredKey |
| Inbox Store | TestGroupInboxStore_NodeNotInitialized, _InvalidJSON, _MissingFields, _AcceptsPushFanoutFields, _UsesProvidedServerAddresses |
| Inbox Retrieve | TestGroupInboxRetrieve_NodeNotInitialized, _InvalidJSON, _MissingGroupId, TestGroupInboxRetrieveCursor_NodeNotInitialized, _InvalidJSON, _MissingGroupId, _PassesOpaqueCursor, _CommandExposed |
| Recovery | TestGroupAcknowledgeRecovery_NotInitialized, _Success |

**File:** `go-mknoon/bridge/bridge_generate_next_key_test.go` (4 tests)

| Test | What it covers |
|------|----------------|
| TestGroupGenerateNextKey_NodeNotInitialized | Uninitialized guard |
| TestGroupGenerateNextKey_InvalidJSON | JSON validation |
| TestGroupGenerateNextKey_MissingGroupId | Missing ID guard |
| TestGroupGenerateNextKey_DoesNotMutateStoredKeyState | Non-destructive generation |

### 12.13 CLI Test Peer (group-relevant subset)
**File:** `go-mknoon/cmd/testpeer/commands_test.go` (4 of 29 tests)

| Test | What it covers |
|------|----------------|
| TestHandleCommandGroupJoinNotStarted | Join without node |
| TestHandleCommandGroupJoinMissingParams | Missing join params |
| TestHandleCommandGroupPublishWithoutIdentity | Publish without identity |
| TestHandleCommandGroupInboxStoreMissingText | Missing inbox text |

### 12.14 Go Integration (group-relevant subset)
**File:** `go-mknoon/integration/media_test.go` (2 of 3 tests)

| Test | What it covers |
|------|----------------|
| TestRelayGroupMediaUploadDownload | Group media relay round-trip with two authorized non-sender downloads and outsider rejection |
| TestRelayGroupMediaVoiceNote | Group voice note relay |

**File:** `go-mknoon/integration/relay_test.go` (1 of 20 tests)

| Test | What it covers |
|------|----------------|
| TestRelayRefreshPreservesJoinedGroupTopics | Topic preservation on refresh |
