# Plan 234 Session 01 — Typed Policy, Encrypted Codec, and v100 Durability

Status: accepted
Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 01
Run mode: implementation-committed gap-closure
Migration owner: Plan 234 / v100 only

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-07-11 10:01:42 +0200 | Evidence Collector | breakdown, source plan, current v99 version/registry, direct model/codec/helper seams | Session 01 is the sole Plan-234 v100 owner; no competing v100 claim exists. | Freeze the typed policy, schema, causal tests, and bounded proof. |
| 2026-07-11 | Local bounded plan fallback | `message_payload.dart`, `conversation_message.dart`, `messages_db_helpers.dart`, migration 097/099 tests and registry, gate cadence | D-234-01..08 are now authoritative in the source plan. Exact v100 columns and constraints below preserve ordinary/legacy behavior while representing fail-closed unsupported policy. No structural blocker remains. | Execute RED-first with independent QA. |

## Problem And Evidence

The direct encrypted payload, `ConversationMessage`, and v99 `messages` schema cannot carry the accepted private-media policy or durable lifecycle seed. That makes every later ingestion, reveal, expiry, and capability session impossible. Session 01 establishes only the shared typed vocabulary, encrypted-inner codec, direct-parent durability, and complete v100 migration chain.

Current anchors:

- `lib/features/conversation/domain/models/message_payload.dart` owns encrypted inner JSON mapping.
- `lib/features/conversation/domain/models/conversation_message.dart` and `lib/core/database/helpers/messages_db_helpers.dart` own direct parent row mapping.
- `lib/core/database/app_database_version.dart` and `lib/core/database/production_migration_registry.dart` currently end at v99.
- `test/core/database/migrations/099_group_messages_is_forwarded_test.dart` is the predecessor preservation pattern.
- The accepted D-234-01..08 contract is persisted in the source plan. No Go/relay authority is selected.

## Scope Contract And Guard

In scope:

- Add `lib/core/media/private_media_policy.dart` with versioned mode, duration, lifecycle state, and fail-closed unsupported parsing vocabulary reusable by Plans 238/242 without presentation imports.
- Add optional typed private policy to the encrypted v2 inner `MessagePayload` JSON only. Missing policy remains ordinary. Unknown version/mode, invalid duration, or malformed known policy becomes typed unsupported; unknown additive fields in a valid v1 policy are ignored.
- Extend `ConversationMessage`, `copyWith`, equality/mapping, direct DB insert/query helpers, and repository mapping for the v100 fields.
- Add and register `100_direct_private_media_lifecycle`; update the DB version to 100 and preserve all v1..v99 artifacts.
- Add focused causal tests, complete-chain proof, exact gate registration, and real SQLCipher proof on the available Android and iOS targets.

Exact v100 column contract on `messages`:

| Column | SQLite contract |
|---|---|
| `private_media_policy_version` | `INTEGER NOT NULL DEFAULT 0 CHECK (private_media_policy_version >= 0)` |
| `private_media_mode` | `TEXT NOT NULL DEFAULT 'ordinary' CHECK (private_media_mode IN ('ordinary','protected','view_once','disappearing','unsupported'))` |
| `private_media_duration_seconds` | `INTEGER CHECK (private_media_duration_seconds IS NULL OR private_media_duration_seconds IN (3600,86400,604800))` |
| `private_media_state` | `TEXT NOT NULL DEFAULT 'none' CHECK (private_media_state IN ('none','available','opening','viewing','consumed','expired','unsupported'))` |
| `private_media_received_at_ms` | `INTEGER CHECK (private_media_received_at_ms IS NULL OR private_media_received_at_ms >= 0)` |
| `private_media_expires_at_ms` | `INTEGER CHECK (private_media_expires_at_ms IS NULL OR private_media_expires_at_ms >= 0)` |
| `private_media_revealed_at_ms` | `INTEGER CHECK (private_media_revealed_at_ms IS NULL OR private_media_revealed_at_ms >= 0)` |
| `private_media_terminal_at_ms` | `INTEGER CHECK (private_media_terminal_at_ms IS NULL OR private_media_terminal_at_ms >= 0)` |
| `private_media_clock_high_water_ms` | `INTEGER CHECK (private_media_clock_high_water_ms IS NULL OR private_media_clock_high_water_ms >= 0)` |

Add `idx_messages_private_media_expiry` on `private_media_expires_at_ms` for disappearing rows. The migration must be rerunnable by checking existing columns/index, must use the shared production registry, and must not touch `media_attachments`, `group_messages`, owner lanes, or v101.

Out of scope:

- Composer/send/receive ordering, notification copy, downloads (Session 02).
- Consume/expiry transitions and cleanup (Session 03).
- Actions/library/Forward/bookmark/PiP qualification (Session 04).
- Native capture protection and private-route UX (Session 05).
- Go/libp2p/relay changes, account-wide consumption, or v101.

Hard guards:

- Never serialize `privateMedia` into a clear outer envelope, v1 plaintext writer, owner-lane field, logs, or relay metadata.
- Never decode unknown/malformed policy as ordinary.
- Never infer ownership from message ID or mutate a same-ID group/unresolved attachment.
- Preserve missing-policy and legacy rows as ordinary with version 0/state `none`.
- Snapshot the dirty worktree and preserve all unrelated pre-existing modifications.

## Test Contract

RED must precede production changes.

1. `test/features/conversation/domain/models/private_media_policy_test.dart`
   - missing policy is ordinary;
   - all four v1 modes and allowed durations validate;
   - private eligibility shape is typed but does not import UI;
   - unknown version/mode, malformed object, invalid duration/combinations become unsupported;
   - unknown additive v1 fields are ignored.
2. Extend `test/features/conversation/domain/models/message_payload_test.dart`
   - valid policy round-trips only through `toInnerJson`/`fromDecryptedJson`;
   - outer/v1 writers never contain `privateMedia`;
   - legacy fixtures remain byte/behavior compatible.
3. Extend/add direct model/helper tests for every v100 field, `copyWith`, row mapping, defaults, and unsupported state.
4. `test/core/database/migrations/100_direct_private_media_lifecycle_test.dart`
   - both create/upgrade registries contain exactly v100 after v99;
   - fresh v100 and real 99->100 upgrade expose exact columns/defaults/CHECK behavior/index;
   - actual entry rerun is idempotent;
   - v96 owner/library, v97 direct Forward, v98 deletion journal, v99 group Forward, same-ID direct/group, and unresolved fixtures preserve values;
   - invalid modes/states/durations/timestamps are rejected;
   - no v101 or group schema delta lands.
5. Extend `test/core/database/integration/full_migration_chain_test.dart` through v100 with fresh, predecessor, wrong-password, downgrade, close/reopen, and run-twice preservation.
6. Add `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart` to prove PRAGMA schema/default/index, 99->100 values, close/reopen, and rerun using real `sqflite_sqlcipher` on explicit available Android and iOS targets.

Representative mutations that must fail: missing policy defaults to protected; unknown mode defaults to ordinary; `privateMedia` appears in outer JSON; v100 is absent from either registry; migration mutates group rows; invalid state/duration is accepted; predecessor `is_forwarded` or owner/library values are lost.

## Implementation Sequence

1. Record RED for the typed policy/codec and v100 migration tests.
2. Implement the shared typed policy and encrypted-inner codec.
3. Extend direct parent model/helper/repository mapping without adding lifecycle behavior.
4. Implement idempotent v100, both registry arms, and version/opener wiring.
5. Register dedicated host/device tests in the owning 1:1 inventories and definitions.
6. Run focused GREEN, predecessor/full-chain sentinels, live SQLCipher proof, curated `1to1`, analyzer on touched files, and scope/diff guards.

## Device/Relay Proof Profile

- Profile: SQLCipher single-device per platform; relay proof N/A by accepted local-only policy.
- Re-resolve before execution:
  - `flutter devices --machine`
  - `adb devices`
  - `xcrun simctl list devices available`
- Expected bounded targets for this run:
  - Android physical: `21071FDF600CSC`
  - Android emulator supporting automation/secondary confidence: `emulator-5554`
  - iOS simulator: `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`
- Required closure proof: run `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart` with `flutter test -d <explicit-id>` once on the available Android physical target and once on the available iOS simulator. The Android emulator is supporting unless the physical target is unavailable.
- Unavailable hardware/OS versions are recorded `N/A (target unavailable by project policy)`, never an environment blocker. A target that is discovered but fails the owned SQLCipher contract is blocking.
- `FLUTTER_DEVICE_ID` alone does not prove paired behavior; no paired/relay claim belongs to this session.

## Acceptance Gates

```bash
git status --short

flutter test test/features/conversation/domain/models/private_media_policy_test.dart
flutter test test/features/conversation/domain/models/message_payload_test.dart
flutter test test/features/conversation/domain/models/conversation_message_test.dart
flutter test test/core/database/helpers/messages_db_helpers_test.dart
flutter test test/core/database/migrations/100_direct_private_media_lifecycle_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Live availability first, then explicit targets.
flutter devices --machine
adb devices
xcrun simctl list devices available
flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 21071FDF600CSC
flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 674DFFF6-5F38-4235-93F6-AF7FBF86AE65

flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list

dart analyze lib/core/media/private_media_policy.dart lib/features/conversation/domain/models/message_payload.dart lib/features/conversation/domain/models/conversation_message.dart lib/core/database/migrations/100_direct_private_media_lifecycle.dart lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart lib/core/database/helpers/messages_db_helpers.dart
git diff --check
git diff --name-only -- go-mknoon go-relay-server lib/features/groups lib/features/announcements
```

No `core-host-all`, `feature-host-all`, or full `host-all` is a Session-01 gate.

## Validated Execution Contract

- Source of truth: this execution-safe Session 01 plan plus accepted decisions D-234-01..08 in `234-1to1-private-media-lifecycle-tdd-plan.md`; higher-precedence `AGENTS.md` availability and gate-cadence rules apply.
- Closure bar: every Done Criterion below, every exact direct command and named gate above, Android `21071FDF600CSC` plus iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` SQLCipher proof, and an independent QA pass with no blocking finding.
- Production owner files: new `private_media_policy.dart` and migration 100; `message_payload.dart`; `conversation_message.dart`; `messages_db_helpers.dart`; `app_database_version.dart`; `production_migration_registry.dart`. Current source verifies `message_repository_impl.dart` already delegates through complete `toMap`/`fromMap`, and `main.dart` already delegates to the shared version/registry, so neither requires an edit unless a causal RED disproves that seam.
- RED-first regressions: the six named host files in Acceptance Gates plus the new Android/iOS SQLCipher proof; ordinary encrypted-media round-trip is the exact preservation sentinel. No regression is `none`.
- Gate/registration owner files: both 1:1 arrays in `scripts/run_test_gates.sh` and `scripts/run_host_test_gates.sh`, plus the exact SQLCipher device record in `Test-Flight-Improv/test-gate-definitions.md`.
- Known-failure interpretation: none is pre-accepted. Any required-command failure is `pending_triage` until a focused slice classifies it; only a failure explicitly allowed by governing gate prose and proven not widened may be `accepted_known_failure`.
- Scope guard/non-goals: no group/announcement/Go/relay/native/presentation/lifecycle-transition/send-receive behavior, no owner-lane mutation, no v101, and no full host-all family gate.
- Pre-existing dirty baseline: preserve `.gitignore`, Graphify artifacts/scripts, `info.plist`, the pre-existing direct media repository/test edits, group tests/fake edits, unrelated mockups, and Plan-234/238 rollout docs. Session-owned additions/edits must remain attributable to the files named here.
- Graph Grounding Snapshot: compact architecture query anchored `MessagePayload` and `ConversationMessage`; graph freshness is stale because of an unrelated group-send file, and helper/registry/gate relationships were therefore verified in current source. No missing graph edge is treated as proof of no dependency.
- Migration ledger: current production head is v99; repository search found no competing v100 implementation/claim. Plan 234 exclusively owns v100; Plan 238 remains reserved v101 and is not consumed.

## Executor Handoff

- Invocation topology: isolated Executor; initial Executor complete; `fix_passes = 2`; independent QA found B2, then accepted the post-fix scope in a new read-only turn. A genuinely new reviewer thread could not be materialized because executor, controller, and root all received `agent thread limit reached`; no local Executor self-review fallback was used.
- Session production delta: new `lib/core/media/private_media_policy.dart`; new `lib/core/database/migrations/100_direct_private_media_lifecycle.dart`; updated encrypted-inner `MessagePayload`, typed `ConversationMessage`, database version 100, and both production registry arms. Existing generic message helper/repository and `main.dart` delegation required no production edit.
- Session test/registration delta: new policy, migration, and SQLCipher tests; extended payload/model/helper/full-chain tests; both 1:1 arrays and the exact device-proof definition updated.
- Causal RED evidence before production: policy command exited 1 because the policy file/types were absent; migration command exited 1 because migration 100/function was absent.
- Executor triage: helper-suite failure was caused by its fixture omitting pre-existing v97 before inserting a model map; full-chain repository fixture stopped at v97 and omitted v100. Both were recorded `pending_triage`, corrected only in test fixtures with the real registry/migration entries, and their exact suites then passed. These are not QA fix passes.
- Worktree attribution: preserve every baseline file listed in Validated Execution Contract. Additional unrelated Plan 244–249 docs appeared concurrently after the initial snapshot; they are not Session 01 work. The forbidden production path guard remained empty.

| Evidence | Exact command | Result / classification | Artifact |
|---|---|---|---|
| Policy | `flutter test test/features/conversation/domain/models/private_media_policy_test.dart` | passed | live command output |
| Encrypted codec | `flutter test test/features/conversation/domain/models/message_payload_test.dart` | passed | live command output |
| Direct model | `flutter test test/features/conversation/domain/models/conversation_message_test.dart` | passed | live command output |
| DB helpers/repository seam | `flutter test test/core/database/helpers/messages_db_helpers_test.dart` | passed (68 tests) | live command output |
| v100 migration | `flutter test test/core/database/migrations/100_direct_private_media_lifecycle_test.dart` | passed | live command output |
| Full migration chain | `flutter test test/core/database/integration/full_migration_chain_test.dart` | passed (15 tests) | live command output |
| Ordinary preservation | `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` | passed | live command output |
| Availability | `flutter devices --machine`; `adb devices`; `xcrun simctl list devices available` | passed; all required explicit IDs available | live command output |
| Android SQLCipher | `flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 21071FDF600CSC` | passed | live device output |
| iOS SQLCipher | `flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 674DFFF6-5F38-4235-93F6-AF7FBF86AE65` | passed | live simulator output |
| Curated 1:1 | `./scripts/run_test_gates.sh 1to1` | passed (1793 tests) | live command output |
| Host inventory | `./scripts/run_host_test_gates.sh 1to1 --list` | passed; 72 commands and all dedicated files listed | live command output |
| Analyzer | exact touched-file `dart analyze` command from Acceptance Gates | passed; no issues | live command output |
| Diff/scope | `git diff --check`; `git diff --name-only -- go-mknoon go-relay-server lib/features/groups lib/features/announcements` | passed; forbidden production output empty | live command output |
| Reverse impact | `python3 graphify-arch/tdd_context.py affected <six changed app-owned files> --budget 600` | passed; expected direct callers surfaced, output truncated at budget and backed by curated caller tests | live command output |

## QA Findings And Dispositions

- `B1` — blocking scope/readability issue from independent parent QA guard: running `dart format` across whole pre-existing files introduced unrelated mechanical churn in `production_migration_registry.dart`, `messages_db_helpers_test.dart`, and `full_migration_chain_test.dart`. Disposition: resolved in fix pass 1 by reconstructing all untouched regions from HEAD while retaining only attributable Session 01 hunks. Post-fix stats are `3/0`, `80/0`, and `165/3` insertions/deletions respectively; migration (3 tests), helper (68), full-chain (15), the exact analyzer scope, and `git diff --check` all pass.
- `B2` — blocking scope-hygiene finding from fresh independent QA: formatter-only changes remained in legacy code at `message_payload_test.dart:16-63,115-170` and `conversation_message_test.dart:51-56`. Disposition: resolved in fix pass 2 by restoring every named legacy hunk byte-for-byte while retaining the new imports/private-media tests. Both diffs are now additive-only (`153/0` and `110/0`); payload (51 tests), conversation model (24), the exact analyzer scope, full `git diff --check`, and forbidden production-path guard all pass. No behavior, migration, registry, gate, RED-first, encrypted-inner, persistence, or SQLCipher-proof blocker was found.
- Post-fix independent QA verdict: `accepted`. `B1` and `B2` are resolved; no new blocking or non-blocking findings remain. The reviewer reconciled every tracked/untracked Session 01 artifact with the persisted RED/GREEN, migration, registry, gate, and Android/iOS SQLCipher evidence.

## Done Criteria

- [x] D-234-01..08 remain persisted and mutually consistent in the source plan.
- [x] First causal tests were observed RED before production code.
- [x] Typed policy and lifecycle vocabulary cover ordinary/protected/view-once/disappearing/unsupported exactly.
- [x] Policy is encrypted-inner-only; legacy/missing/additive/unknown behavior matches D-234-07.
- [x] Conversation model/helper/repository round-trip all v100 fields.
- [x] v100 is the sole new migration, appears in both registries, and preserves v1..v99 plus sibling-owner fixtures.
- [x] Host migration/full-chain and real Android+iOS SQLCipher proof pass on available explicit targets.
- [x] Focused tests, exact sentinels, curated `1to1`, analyzer, and diff/scope guards pass.
- [x] Independent QA records a trustworthy execution verdict and no out-of-scope mutation.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 10:56:55 CEST | final verdict | one incremental architecture refresh; final diff/scope and registration guards; complete evidence/QA reconciliation | Graphify refresh passed (`46810` nodes, `72852` edges; overlay `1247` files/`12192` tests/`945` targets); final QA `accepted`; all Done Criteria checked; verdict `accepted` | stop execution and hand the persisted result to the closure controller |
| 2026-07-11 10:55:15 CEST | after post-fix independent QA | full tracked/untracked Session 01 scope, B1/B2 dispositions, persisted evidence ledger | QA verdict `accepted`; no blocking or non-blocking findings; thread-cap forced a new read-only turn on the independent reviewer after all three spawn layers failed, with no Executor self-review fallback | run exactly one incremental Graphify refresh, then persist the final accepted execution result |
| 2026-07-11 10:52:06 CEST | after QA fix pass 2 | restored legacy payload/model test hunks; both focused suites; exact analyzer; full diff/scope guards | `B2` resolved; payload 51/51 and model 24/24 passed, analyzer/diff/scope clean, diffs additive-only `153/0` and `110/0`; `fix_passes = 2` | launch a fresh final independent QA pass; if accepted, refresh Graphify once and persist final verdict |
| 2026-07-11 10:50:39 CEST | before QA fix pass 2 | fresh QA inspected all tracked/untracked Session 01 sources/tests and evidence | verdict `not_accepted` solely for `B2` legacy-test formatter churn; `B1` confirmed resolved; no behavior or proof blocker; `fix_passes = 2` | restore exact legacy hunks in the two model tests, rerun their focused proof/analyzer/diff check, then launch fresh QA |
| 2026-07-11 10:45:02 CEST | after QA fix pass 1 | reconstructed registry/helper/full-chain untouched regions; migration/helper/full-chain exact tests; analyzer; diff stats/check | `B1` resolved; tests passed 3/68/15, analyzer clean, `git diff --check` clean; attributable stats `3/0`, `80/0`, `165/3`; `fix_passes = 1` | launch a fresh independent QA reviewer against the cleaned scope and persisted evidence |
| 2026-07-11 10:41:09 CEST | before QA fix pass 1 | independent scope guard; diffs for registry/helper/full-chain | `B1` blocking: broad formatter churn obscures attributable changes; `fix_passes = 1`; no behavior finding and no production/test command failure | reconstruct the three files from HEAD formatting with only Session 01 hunks, rerun exact affected proof/analyzer/diff guard, then launch a fresh QA pass |

## Final Execution Verdict

`accepted`

Session 01 is complete with no blocking or non-blocking QA finding. Two bounded scope-hygiene fix passes restored formatter-only legacy regions; no behavior fix pass was required. No commit was created.

## Execution Result

- Final verdict: `accepted`.
- Invocation topology: isolated Executor with non-overlapping independent QA. Fix pass 1 resolved `B1`; fix pass 2 resolved `B2`. Executor, controller, and root all received `agent thread limit reached` when materializing a genuinely new post-fix reviewer thread, so the already-independent QA reviewer performed a new read-only post-fix turn and returned `accepted`. This topology deviation is disclosed; no Executor self-review was substituted.
- Independent QA used: yes; it inspected the plan, dirty baseline, tracked diffs, every untracked Session 01 artifact, tests, and evidence. Final finding set is empty.
- Local sequential fallback used: no.
- Files changed: `lib/core/media/private_media_policy.dart`; `lib/features/conversation/domain/models/message_payload.dart`; `lib/features/conversation/domain/models/conversation_message.dart`; `lib/core/database/migrations/100_direct_private_media_lifecycle.dart`; `lib/core/database/app_database_version.dart`; `lib/core/database/production_migration_registry.dart`; both 1:1 gate scripts; `Test-Flight-Improv/test-gate-definitions.md`; and this execution work surface. Generic `messages_db_helpers.dart`, `message_repository_impl.dart`, and `main.dart` already provided complete mapping/registry delegation and were not changed.
- Tests added or updated: new policy, v100 migration, and Android/iOS SQLCipher proof tests; extended payload, conversation-model, message-helper, and full-migration-chain tests. Both 1:1 inventories register the dedicated host proof files.
- Evidence workdir: `/Users/I560101/Project-Sat/mknoon-2/flutter_app` for every command below.

| Evidence | Exact command | Exit/result | Classification | Log/artifact |
|---|---|---|---|---|
| Causal policy RED | `flutter test test/features/conversation/domain/models/private_media_policy_test.dart` | exit 1 before production because the policy file/types were absent | `passed` (required causal RED observed) | live output; no separate log |
| Causal migration RED | `flutter test test/core/database/migrations/100_direct_private_media_lifecycle_test.dart` | exit 1 before production because migration 100/function was absent | `passed` (required causal RED observed) | live output; no separate log |
| Policy | `flutter test test/features/conversation/domain/models/private_media_policy_test.dart` | exit 0 | `passed` | live output; no separate log |
| Encrypted codec | `flutter test test/features/conversation/domain/models/message_payload_test.dart` | exit 0; 51 tests | `passed` | live output; no separate log |
| Direct model | `flutter test test/features/conversation/domain/models/conversation_message_test.dart` | exit 0; 24 tests | `passed` | live output; no separate log |
| DB helper/repository seam | `flutter test test/core/database/helpers/messages_db_helpers_test.dart` | exit 0; 68 tests | `passed` | live output; no separate log |
| v100 migration | `flutter test test/core/database/migrations/100_direct_private_media_lifecycle_test.dart` | exit 0; 3 tests | `passed` | live output; no separate log |
| Full migration chain | `flutter test test/core/database/integration/full_migration_chain_test.dart` | exit 0; 15 tests | `passed` | live output; no separate log |
| Ordinary preservation sentinel | `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` | exit 0 | `passed` | live output; no separate log |
| Live availability | `flutter devices --machine`; `adb devices`; `xcrun simctl list devices available` | exit 0; Android `21071FDF600CSC`, emulator `emulator-5554`, iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` available | `passed` | live output; no separate log |
| Android SQLCipher | `flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 21071FDF600CSC` | exit 0 | `passed` | live physical-device output; no separate log |
| iOS SQLCipher | `flutter test integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart -d 674DFFF6-5F38-4235-93F6-AF7FBF86AE65` | exit 0 | `passed` | live simulator output; no separate log |
| Curated 1:1 | `./scripts/run_test_gates.sh 1to1` | exit 0; 1793 tests | `passed` | live output; no separate log |
| Host inventory | `./scripts/run_host_test_gates.sh 1to1 --list` | exit 0; 72 commands and all dedicated files listed | `passed` | live output; no separate log |
| Analyzer | `dart analyze lib/core/media/private_media_policy.dart lib/features/conversation/domain/models/message_payload.dart lib/features/conversation/domain/models/conversation_message.dart lib/core/database/migrations/100_direct_private_media_lifecycle.dart lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart lib/core/database/helpers/messages_db_helpers.dart` | exit 0; no issues | `passed` | live output; no separate log |
| Diff guard | `git diff --check` | exit 0 | `passed` | live output; no separate log |
| Forbidden scope guard | `git diff --name-only -- go-mknoon go-relay-server lib/features/groups lib/features/announcements` | exit 0; empty | `passed` | live output; no separate log |
| Reverse impact | `python3 graphify-arch/tdd_context.py affected lib/core/media/private_media_policy.dart lib/features/conversation/domain/models/message_payload.dart lib/features/conversation/domain/models/conversation_message.dart lib/core/database/migrations/100_direct_private_media_lifecycle.dart lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart --budget 600` | exit 0; expected direct callers surfaced | `passed` | live output; no separate log |
| Architecture refresh | `./graphify-arch/refresh_arch_graph.sh --incremental` | exit 0; graph and TDD overlay refreshed once | `passed` | `graphify-arch/graphify-out/graph.json`; `graphify-arch/tdd-overlay.json` |

- QA findings and dispositions: `B1` resolved in fix pass 1; `B2` resolved in fix pass 2; post-fix independent QA returned `accepted`; no `N` findings.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none.
- Safety: the versioned policy is confined to encrypted v2 inner JSON, legacy/malformed/unknown behavior is covered, all direct parent fields persist through model/helper/repository seams, v100 is idempotent and registered in both production arms, v1..v99 and same-ID group/unresolved fixtures are preserved, Android/iOS SQLCipher proof and the curated 1:1 gate pass, forbidden production areas are untouched, and the final scoped diff is attributable.

## Session Closure Audit

- Closure verdict: `closed`; breakdown ledger status: `accepted`.
- What is now closed: Session 01's typed/versioned policy, encrypted-inner codec, direct-parent v100 schema/mapping, complete migration-chain preservation, explicit Android/iOS SQLCipher proof, gate registration, and ordinary-media sentinel.
- Residual-only items: none for Session 01.
- Still-open items: Sessions 02-06 remain program work and are not Session-01 residuals; Session 02 is now dependency-satisfied.
- Accepted differences: privacy state is device-local; no Go/relay authority or account-wide consume claim was added; v101 remains reserved for Plan 238.
- Reopen rule: reopen Session 01 only for a regression in policy parsing/serialization, direct-parent persistence, v100 migration preservation/idempotency, gate registration, or SQLCipher behavior—not for work already assigned to Sessions 02-06.
- Maintenance safety: focused policy/codec/model/helper/migration/full-chain tests, the registered SQLCipher proof, the curated `1to1` gate, and the v100/v101 ownership guard remain the closure reference.
