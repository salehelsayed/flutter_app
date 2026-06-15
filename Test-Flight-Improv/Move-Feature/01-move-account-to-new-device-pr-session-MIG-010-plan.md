# MIG-010 Plan: Pending Work Ownership and Queue Migration

Status: closed (MIG-010 scope only; program still open; MIG-006 deferred-last remains evidence-gated)

## Planning Progress

- 2026-06-07 21:38 CEST - Arbiter completed. Files inspected since last update: reviewer notes, mandatory section scan, simulator/user-override conflict, gate list, and scope guard. Decision/blocker: execution-ready for MIG-010 only; no structural blocker remains; group simulator/release evidence stays deferred-last with MIG-006 by user override. Next action: execute MIG-010 from this doc-scoped plan.
- 2026-06-07 21:37 CEST - Reviewer completed. Files inspected since last update: completed draft, source proposal pending-work requirements, breakdown MIG-010 row, `test-gate-definitions.md`, and named gate script. Decision/blocker: reviewer pass after requiring an explicit pending-work coverage ledger and clarifying that host group coverage is allowed while MIG-006 group simulator evidence remains excluded. Next action: Arbiter classifies the plan.
- 2026-06-07 21:36 CEST - Planner completed. Files inspected since last update: account-migration manifest patterns, pending message retrier, 1:1 retry/upload use cases, introduction outbox delivery, post media/follow-on helpers, group pending repair/membership/reaction outbox repositories, and existing tests. Decision/blocker: draft narrows MIG-010 to a pending-work manifest/validator and ownership policy rather than a broad exporter/importer or UI rewrite. Next action: Reviewer checks completeness, gates, and override compliance.
- 2026-06-07 21:35 CEST - Evidence Collector completed. Files inspected since last update: source proposal pending-work rows, breakdown MIG-010 row, `PendingMessageRetrier`, conversation retry/upload/unacked use cases, introduction outbox helpers, post media/follow-on helpers, group pending key repair/membership/reaction outbox repositories, existing account-migration file/group manifest builders, and gate definitions. Decision/blocker: current code has retry/runtime seams and file/group manifest slices, but no account-migration pending-work ownership manifest proving what resumes on the new phone versus blocks/pauses. Next action: Planner drafts the narrow contract.
- 2026-06-07 21:35 CEST - Evidence Collector started. Files inspected since last update: session breakdown MIG-010 row, source proposal pending-work requirements/gaps, graphify query for MIG-010, and missing-plan check. Decision/blocker: plan artifact was absent and must be created before implementation; MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed. Next action: inspect pending-work owner files, tests, and gate definitions, then draft a narrow doc-scoped MIG-010 plan.

## Execution Progress

- 2026-06-07 22:19 CEST - QA Reviewer completed a read-only review. Verdict: no code/behavior blocker in the pending-work manifest implementation; docs correctly avoid final acceptance overclaim and keep MIG-006 deferred-last. The reviewer found one documentation blocker in `codebase-test-inventory.md` where the feature index still said account_migration had 24 tests while the section now listed 32; the controller fixed the index count and update note. No MIG-006 group simulator/release evidence was run.
- 2026-06-07 22:10 CEST - Controller closure/doc-sync phase completed for the MIG-010 artifacts. Source proposal, session breakdown, plan verdict, gate definitions, and codebase test inventory now record MIG-010 as closed for its own scope only, while MIG-011, MIG-012, and deferred-last MIG-006 remain open. No MIG-006 group simulator/release evidence was run.
- 2026-06-07 22:07 CEST - Local fallback verification passed after the model-contract correction. Commands passed: direct pending-work builder/validator tests `+7`; targeted analyzer with no issues; affected retrier/repository/account-migration direct bundle `+64`; required host gates for baseline (host `+105`, loading smoke `+7`, posts fake `+1`), `1to1` (`+74`), host-side `groups` (`+324`), `posts` (presence `+3` plus posts fake phases 1/2/4/5 green), `intro` (`+205`), completeness-check `803/803`, and `git diff --check`. The host-side `groups` gate is not MIG-006 group simulator/release evidence.
- 2026-06-07 21:59 CEST - Controller verification found the initial local fallback implementation had a pending-work model/builder contract mismatch and the direct tests failed at compile time. The controller patched `migration_pending_work_manifest.dart` to match the builder/tests and continued with focused verification. This was a local execution recovery, not a product-scope expansion.
- 2026-06-07 21:53 CEST - Executor current phase: focused MIG-010 implementation and direct verification complete; final handoff/doc update in progress. Files inspected/touched: existing MIG-005/MIG-006 file/group manifest model/builder/validator/tests, retry/outbox helper and migration row-shape files for 1:1/media/posts/introductions/groups, new `migration_pending_work_manifest.dart`, new `migration_pending_work_manifest_builder.dart`, new `migration_pending_work_manifest_validator.dart`, new builder/validator direct tests, and this plan. Current command/blocker: no blocker; `flutter test test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart test/features/account_migration/application/migration_pending_work_manifest_validator_test.dart` passed 7/7; `dart format --set-exit-if-changed ...` passed with 0 changed; targeted `flutter analyze ...` passed with no issues. Next action: run `graphify update .`, record that result if needed, then final handoff; MIG-006 group simulator/release evidence remains deferred-last, not failed and not closed.
- 2026-06-07 21:42 CEST - Executor started. Owner files inspected: `migration_file_manifest.dart`, `migration_file_manifest_builder.dart`, `migration_file_manifest_validator.dart`, `migration_group_manifest.dart`, `migration_group_manifest_builder.dart`, `migration_group_manifest_validator.dart`, existing file/group manifest tests, graphify MIG-010 query, and worktree status. Decision/blocker: proceed with MIG-010-only pending-work model/builder/validator and required direct tests; MIG-006 group simulator/release evidence remains deferred-last, not failed and not closed.
- 2026-06-07 21:40 CEST - Controller extracted the MIG-010 execution contract from this plan. Scope: add a pending-work manifest/model/builder/validator and direct tests proving new-phone-only resume policy and unsafe pending-work blocking/paused classification across 1:1, media, posts, introductions, and group pending work. Required first tests: `migration_pending_work_manifest_builder_test.dart` and `migration_pending_work_manifest_validator_test.dart`. Required host gates: baseline, 1to1, groups, posts, intro, completeness-check; no MIG-006 group simulator or release-evidence commands. Decision/blocker: ready to spawn Executor with explicit request `model: gpt-5.5`, `reasoning_effort: xhigh`. Next action: spawn Executor.
- 2026-06-07 21:41 CEST - Spawned Executor agent `019ea39a-e783-73f0-bc05-cc802aaec57e` with explicit request `model: gpt-5.5`, `reasoning_effort: xhigh`. Current phase: Executor running under bounded wait. Current command/log: waiting for child result; no local MIG-010 implementation work is running in the controller. Decision/blocker state: `executor_running_pending_evidence`. Next action: wait for Executor code/test evidence, then spawn QA Reviewer if a coherent implementation lands.
- 2026-06-07 21:46 CEST - First bounded wait for Executor agent `019ea39a-e783-73f0-bc05-cc802aaec57e` timed out without a final handoff. Current phase: Executor still running. Current command/log: none available to controller. Decision/blocker state: `executor_wait_timeout_once`; not a product blocker. Next action: perform one additional bounded wait before deciding whether to request progress or recover.
- 2026-06-07 21:51 CEST - Second bounded wait for Executor agent `019ea39a-e783-73f0-bc05-cc802aaec57e` timed out without a final handoff. Current phase: request in-band progress from the Executor before recovery. Current command/log: none available to controller. Decision/blocker state: `executor_wait_timeout_twice`; not yet a product blocker. Next action: send progress request requiring touched files, current command, and whether a coherent patch exists.
- 2026-06-07 21:53 CEST - Executor agent `019ea39a-e783-73f0-bc05-cc802aaec57e` did not respond to the in-band progress request within the bounded wait and was closed while still running. No code/test handoff was produced. Blocker class: `spawn_or_tool_no_completion` for execution delivery only, not a product blocker. Next action: use the documented local execution fallback in the controller, limited to the execution-ready MIG-010 plan.

## real scope

MIG-010 owns pending-work ownership and queue migration semantics for the Move Account MVP. The session should add a migration-owned pending-work manifest and validator that classifies pending local work as one of:

- valid to resume only on the new phone after active commit
- unsafe and migration-blocking before success
- safe to migrate but paused/failed with explicit local state
- outside the migration pending-work surface

The scope covers pending 1:1 messages, retry jobs, unacked inbox sends, upload-pending chat media, app-owned pending upload files, pending post media uploads, pending post deliveries/follow-on outbox jobs, introduction outbox deliveries and pending responses, group retry/inbox repair work, group pending key repairs, group pending membership messages, and group reaction replay outbox rows.

This session should not build the full bundle exporter/importer or final device acceptance. It should create the durable row-level ownership contract that later exporter/importer work consumes.

## closure bar

MIG-010 closes when pending-work rows across the listed surfaces produce a deterministic migration pending-work manifest with stable source-table/source-id/kind/resume-policy data and explicit blocking issues for unsafe rows.

Coverage ledger:

| requirement | required proof |
|---|---|
| Draft/local unsent user data may migrate as local account data | manifest distinguishes local draft/composer-style pending rows from network retry jobs or records them as out of scope with an accepted difference |
| Committed failed/sending 1:1 sends and unacked `wire_envelope` rows migrate safely | builder tests classify valid outgoing `messages` rows and preserve stable message ids/status/transport/wire-envelope ownership |
| Upload-pending chat media and app-owned pending upload files migrate safely | builder/validator tests require app-owned relative pending-upload paths and reuse MIG-005 file manifest coverage for bytes/checksums |
| Pending post media uploads and post delivery/follow-on outbox jobs migrate safely | builder/validator tests cover `post_media_upload_recovery`, post delivery statuses, and `post_follow_on_outbox_*` retry rows |
| Introduction outbox deliveries and pending responses migrate safely | builder/validator tests cover retryable `introduction_outbox_deliveries` and `pending_introduction_responses` with target/sender/action identity |
| Group retry/inbox repair work migrates safely | builder/validator tests cover failed/sending group messages, group inbox retry payload rows, group pending key repairs, pending membership messages, and reaction replay outbox rows |
| Unsafe items block success or remain paused/failed explicitly | validator tests create blocking issues for missing target peer/group/post ids, missing required raw envelopes/payloads, unsupported pending file paths, terminal-but-still-retryable contradictions, and private-material leakage in pending payload fields |
| Old phone never resumes copied jobs after migrated-out | closure notes rely on MIG-009 runtime gate plus MIG-010 manifest ownership tests that no item has an old-phone resume policy after commit |
| Valid pending work resumes only on new phone | manifest policy records `resumeOnNewPhoneAfterCommit` or equivalent and tests assert no source-device resume policy is emitted |

## source of truth

Primary source:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`

Reusable breakdown:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`

Prerequisite session evidence:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-004-plan.md`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-005-plan.md`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md`

Named gates:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Current code and tests win over stale prose when row names or retry semantics differ.

## session classification

Implementation-ready for host-side pending-work ownership and queue-migration contract.

Simulator/device evidence remains intentionally bounded by the user override: do not run MIG-006 group simulator or release-evidence commands in this session. A narrow non-group simulator path may be recorded if available, but lack of MIG-006 group simulator evidence is not a MIG-010 failure.

## exact problem statement

MIG-005 proves pending upload files can be included in the file manifest, MIG-008 proves cutover primitives, and MIG-009 prevents a migrated-out old phone from restarting runtime work. The remaining gap is data ownership: no current migration artifact says which pending drafts, sends, retries, uploads, post jobs, introduction jobs, and group repair jobs are safe to carry into the account bundle and resume on the new phone after commit.

Without a pending-work ownership manifest, a later exporter/importer can silently drop pending work, resume the same job on both phones, or import an unsafe job whose required payload/file/target context is missing.

## files and repos to inspect next

Account-migration manifest pattern:

- `lib/features/account_migration/domain/models/migration_file_manifest.dart`
- `lib/features/account_migration/application/migration_file_manifest_builder.dart`
- `lib/features/account_migration/application/migration_group_manifest_builder.dart`
- new pending-work model/builder/validator files under `lib/features/account_migration/`

1:1 and media pending work:

- `lib/core/services/pending_message_retrier.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/media/media_file_manager.dart`

Posts:

- `lib/features/posts/application/pending_post_media_upload_retrier.dart`
- `lib/features/posts/application/pending_post_delivery_retrier.dart`
- `lib/features/posts/application/pending_post_follow_on_retrier.dart`
- `lib/core/database/helpers/post_media_upload_recovery_db_helpers.dart`
- `lib/core/database/helpers/post_follow_on_outbox_db_helpers.dart`
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/core/database/helpers/post_recipients_db_helpers.dart`

Introductions:

- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
- `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`

Groups:

- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart`
- `lib/core/database/helpers/group_pending_membership_messages_db_helpers.dart`
- `lib/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart`
- group pending/reaction repository implementations under `lib/features/groups/domain/repositories/`

## existing tests covering this area

Existing tests cover retry behavior and row round trips, but not migration ownership:

- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/core/services/pending_message_retrier_stuck_sending_test.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`
- `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart`
- `test/core/services/pending_post_media_upload_retrier_test.dart`
- `test/core/services/pending_post_delivery_retrier_test.dart`
- `test/core/services/pending_post_follow_on_retrier_test.dart`
- `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`
- `test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart`
- `test/core/database/migrations/033_posts_follow_on_outbox_test.dart`
- `test/core/database/migrations/034_posts_media_upload_recovery_test.dart`
- `test/core/database/migrations/046_pending_introduction_responses_test.dart`
- `test/core/database/migrations/054_group_reaction_replay_outbox_test.dart`
- `test/core/database/migrations/063_group_pending_key_repairs_test.dart`
- `test/core/database/migrations/072_group_pending_membership_messages_test.dart`
- MIG-005 file manifest tests cover pending upload files and post media recovery file paths.
- MIG-006 group manifest tests cover pending group key repairs and pending membership metadata, but not queue ownership/resume policy.
- MIG-009 runtime gate tests cover old-phone non-resume after migrated-out, but not new-phone queue ownership after import.

## regression/tests to add first

Add these direct tests before or alongside implementation:

- `test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart`
  - valid 1:1 failed/sending/unacked rows become `resumeOnNewPhoneAfterCommit`
  - valid upload-pending chat media rows reference app-owned pending upload files and source message ids
  - valid post media recovery, post recipient delivery, and follow-on outbox rows preserve post/event/recipient identity
  - valid introduction outbox and pending response rows preserve target/sender/action identity
  - valid group failed/sending/inbox retry, pending key repair, pending membership, and reaction replay rows preserve group/message/reaction identity
  - manifest never emits an old-phone resume policy
- `test/features/account_migration/application/migration_pending_work_manifest_validator_test.dart`
  - missing target peer/group/post/message ids produce blocking issues
  - missing required raw envelope, inbox retry payload, replay payload, or local pending file context produces blocking or paused/failed policy
  - terminal delivered rows are excluded from retry ownership
  - unsupported absolute pending-upload paths and missing app-owned pending files remain blocking through the MIG-005 file-manifest contract
  - private key/raw group key material in pending payload-like fields is reported as blocking sensitive-material leakage
- Update existing file/group manifest tests only if the pending-work builder needs an explicit shared model hook.

## step-by-step implementation plan

1. Add `MigrationPendingWorkManifest` domain models with item kind, source table, source id, related account/group/thread ids, current status, resume policy, and issue types. Keep it serializable and deterministic.
2. Add `MigrationPendingWorkManifestBuilder` under `lib/features/account_migration/application/`. It should accept raw row iterables, following the existing MIG-004/MIG-005/MIG-006 manifest-builder pattern, and should not open the DB itself.
3. Map rows into explicit kinds: `oneToOneMessageRetry`, `oneToOneUnackedInboxStore`, `chatMediaUpload`, `postMediaUpload`, `postDelivery`, `postFollowOn`, `introductionOutbox`, `pendingIntroductionResponse`, `groupMessageRetry`, `groupInboxStoreRetry`, `groupPendingKeyRepair`, `groupPendingMembership`, and `groupReactionReplay`.
4. Add validator rules for missing ownership identity, missing required payloads/envelopes, terminal rows that should not be retried, unsupported pending-upload paths, and sensitive private-material leakage in payload fields. Prefer blocking issues when silent duplication/loss is possible.
5. Reuse MIG-005 file-manifest behavior for file bytes/checksums rather than duplicating checksum logic in MIG-010. The pending-work manifest should point to source rows and required app-owned paths; the file manifest remains the file integrity proof.
6. Add direct builder/validator tests first, then implement until they pass.
7. Run existing retrier/repository tests to confirm the ownership model did not change runtime retry behavior accidentally.
8. Update the source proposal and breakdown closure deltas only after direct tests and named gates pass.

## risks and edge cases

- A pending item can be valid as data but unsafe to auto-resume, especially when a required target peer, group id, raw envelope, inbox retry payload, or local file is missing.
- Some rows are already covered by file/group manifests; MIG-010 should reference those proofs rather than duplicating file checksums or group key validation.
- Old-phone non-resume is runtime-gated by MIG-009; MIG-010 should not reimplement runtime gates, but it must not emit a policy that says the old phone owns copied work after commit.
- Group pending work can imply multi-device behavior. Host-side manifest tests are in scope; MIG-006 group simulator/release evidence remains deferred-last by explicit user override.
- Pending work must not serialize private key material, raw group key bytes, or raw media secret values inside migration metadata.

## exact tests and gates to run

Direct MIG-010 tests:

```sh
flutter test \
  test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart \
  test/features/account_migration/application/migration_pending_work_manifest_validator_test.dart
```

Affected existing direct tests:

```sh
flutter test \
  test/features/account_migration/application/migration_file_manifest_builder_test.dart \
  test/features/account_migration/application/migration_group_manifest_builder_test.dart \
  test/core/services/pending_message_retrier_test.dart \
  test/core/services/pending_message_retrier_upload_ordering_test.dart \
  test/core/services/pending_message_retrier_stuck_sending_test.dart \
  test/features/introduction/application/introduction_outbound_delivery_test.dart \
  test/features/posts/improvement/post_media_upload_recovery_repository_test.dart \
  test/core/services/pending_post_media_upload_retrier_test.dart \
  test/core/services/pending_post_delivery_retrier_test.dart \
  test/core/services/pending_post_follow_on_retrier_test.dart \
  test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart \
  test/core/database/helpers/group_pending_membership_messages_db_helpers_test.dart
```

Named host gates:

```sh
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh completeness-check
```

Narrow non-MIG-006 simulator evidence, only if devices are available after host gates and only if implementation changes runtime delivery behavior rather than manifest-only validation:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" intro --list
```

Do not run MIG-006 group simulator or group release-evidence commands during MIG-010.

## known-failure interpretation

- MIG-006 remains deliberately deferred-last/evidence-gated for commands 29-123 and final group verification. Missing MIG-006 group simulator/release evidence is not a MIG-010 failure and must not be marked closed by this session.
- If host `groups`, `posts`, `intro`, or `1to1` fail because MIG-010 changed row classification or manifest behavior, that is in scope.
- If simulator/device availability blocks narrow non-group simulator evidence, record it as evidence-gated instead of green.
- Pre-existing unrelated test failures are not MIG-010 acceptance unless a direct MIG-010 test or touched named gate regresses.

## done criteria

- New pending-work manifest model, builder, and validator exist and are deterministic.
- The coverage ledger requirements are proven by direct tests or explicitly marked as accepted differences with evidence.
- Unsafe pending work produces blocking or paused/failed issues instead of silent drop or duplicate resume.
- No pending-work manifest item assigns resume ownership to the old phone after commit.
- Existing retry/repository tests still pass for touched surfaces.
- Required named host gates pass or have clear unrelated known-failure evidence.
- Source proposal, session breakdown, and this plan record that MIG-010 is closed for its own scope only and that MIG-006 remains deferred-last/evidence-gated.

## scope guard

Do not implement the full account bundle exporter/importer.

Do not implement user-facing pending-work UI; MIG-011 owns UX.

Do not rerun or close MIG-006 group simulator/release evidence.

Do not change normal retrier runtime behavior unless a direct ownership test proves the manifest cannot be correct without a small row-state fix.

Do not add a second device model or sibling-device semantics. The policy remains account move, new-phone-only resume after commit.

## accepted differences / intentionally out of scope

- MIG-010 produces a pending-work ownership manifest and validator, not physical iOS-to-iOS end-to-end proof.
- File byte integrity stays in the MIG-005 file manifest; MIG-010 references required app-owned pending paths and rows.
- Group key/pending membership cryptographic continuity stays in MIG-006; MIG-010 records queue ownership and unsafe-row policy only.
- Old-phone runtime non-resume is proven by MIG-009 gates; MIG-010 proves no migrated pending-work policy reassigns ownership back to the old phone.

## dependency impact

MIG-010 gives MIG-011 and MIG-012 a stable pending-work contract to surface in UI and final acceptance. If MIG-010 is revised, MIG-011 must not claim clear pending-work failure/progress states, and MIG-012 must not claim no duplicate or silent-loss behavior until the pending-work manifest/validator is restored.

MIG-006 remains deliberately deferred-last/evidence-gated by hard user override and is not a dependency for executing MIG-010 host-side implementation.

## closure progress

- Closed code: `migration_pending_work_manifest.dart`, `migration_pending_work_manifest_builder.dart`, `migration_pending_work_manifest_validator.dart`, `migration_pending_work_manifest_builder_test.dart`, and `migration_pending_work_manifest_validator_test.dart`.
- Covered behavior: deterministic row-driven pending-work ownership manifesting for 1:1 retry/unacked rows, chat-media pending uploads, post media/delivery/follow-on rows, introduction outbox/pending-response rows, and group retry/inbox/key-repair/membership/reaction replay rows.
- Unsafe-row behavior: blocking, pause, or fail issues now cover missing ownership identity, missing required payload/file context, unsupported pending paths, terminal retry contradictions, and sensitive private-material leakage.
- Evidence: direct pending-work builder/validator tests `+7`, affected direct retrier/repository/account-migration bundle `+64`, targeted analyzer clean, baseline host `+105` plus loading smoke `+7` plus posts fake `+1`, `1to1` `+74`, host-side `groups` `+324`, posts gate presence `+3` plus fake phases 1/2/4/5 green, intro `+205`, completeness-check `803/803`, `git diff --check`, and read-only QA review after fixing the inventory count note.
- Accepted differences: this session produces a manifest/validator contract only. It does not implement full exporter/importer consumption, actual imported queue resume, user-facing pending-work UI, final physical-device acceptance, or MIG-006 group release evidence. Pending drafts or composer-local unsent data outside the covered committed row surfaces remain explicit final-acceptance scope.

## session verdict

MIG-010 is closed for its own pending-work ownership and queue-migration manifest scope only.

The overall Move Account doc remains open. MIG-011 and MIG-012 still need execution, and MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final group verification still required. This plan does not claim final Move Account acceptance.
