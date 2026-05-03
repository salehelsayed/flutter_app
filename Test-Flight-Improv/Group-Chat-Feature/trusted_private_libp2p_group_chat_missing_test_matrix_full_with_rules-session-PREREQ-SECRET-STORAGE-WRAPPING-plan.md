# Session PREREQ-SECRET-STORAGE-WRAPPING Plan - Group Media And Group Key Secret Wrapping

Status: qa_passed

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T21:38:00+02:00 | Evidence Collector completed | DB-006 source row; DB-006 plan; `test-inventory.md`; breakdown row 56; SQLite repo map; `secure_key_store.dart`; `media_attachment_repository_impl.dart`; `media_attachments_db_helpers.dart`; `group_repository_impl.dart`; `group_keys_db_helpers.dart`; `main.dart`; media/group-key helper and repository tests | Repo-owned prerequisite. Existing identity and DB-key evidence is green, but `media_attachments.encryption_key_base64` and `group_keys.encrypted_key` still hold plaintext-equivalent key values in ordinary SQL rows. | Draft the narrow secure-reference plan. |
| 2026-05-01T21:39:00+02:00 | Planner completed | Same evidence set plus `MediaAttachment`, `GroupKeyInfo`, full migration-chain schema expectations | Use secure-store-backed references and post-open legacy scrubbing, not a broad schema rewrite. Existing columns can remain as references if raw SQL no longer contains key material and repository reads still hydrate models. | Run local sufficiency review. |
| 2026-05-01T21:40:00+02:00 | Reviewer completed | Draft scope, closure bar, tests, gates, known failures | Sufficient with one required guardrail: production must call the legacy scrub before repositories can expose existing plaintext rows, and startup mirroring must hydrate group key material before writing to the shared push key store. | Fold guardrail into arbiter decision. |
| 2026-05-01T21:41:00+02:00 | Arbiter completed | Final plan and scope guard | `execution-ready`: no structural blocker remains. DB-006 can close only after repository and post-open scrub tests prove raw SQL rows contain references, secure storage contains the material, and loaded models still expose keys to existing application code. | Run Execution+QA. |

## Run Mode

- Active mode: implementation-committed gap-closure.
- Reopened prerequisite: `PREREQ-SECRET-STORAGE-WRAPPING`.
- Owned source row: DB-006.
- Source row state at planning intake: DB-006 `Partial`.
- Intended closure effect: move DB-006 to `Covered` only after group media object keys and group key material are removed from ordinary SQL rows or replaced with non-secret secure-store references, while existing repository consumers can still load the required key material.
- Device/relay defaults verified earlier on 2026-05-01, but this session is host-only because the blocker is local durable storage and table-inspection evidence.

## Real Scope

Implement the smallest production-owned secret wrapping slice for DB-006:

- store group media per-object keys in `SecureKeyStore` when `MediaAttachmentRepositoryImpl` is constructed with a secure store
- persist only a deterministic secure-store reference in `media_attachments.encryption_key_base64` for production repository writes
- hydrate secure-store-backed media keys when repository reads attachments
- store group key material in the primary `SecureKeyStore` when `GroupRepositoryImpl.saveKey` is constructed with that store
- persist only a deterministic secure-store reference in `group_keys.encrypted_key` for production repository writes
- hydrate secure-store-backed group keys for `getLatestKey`, `getKeyByGeneration`, pruning, and shared-push mirroring
- add an idempotent post-open scrub that migrates existing plaintext-equivalent media keys and group keys from SQL rows into secure storage and rewrites the SQL value to the same reference form
- wire the scrub and secure-store-backed repositories in `main.dart`

This session does not redesign media encryption, rotate historical keys, rebuild tables, change wire payloads, or claim that encrypted media/key material is absent from network payloads. It only closes the ordinary SQL table persistence blocker.

## Closure Bar

DB-006 may move to `Covered` only when:

- repository saves of encrypted media attachments write the actual key to `SecureKeyStore` and raw SQL stores only an opaque reference
- repository reads hydrate media attachment keys from `SecureKeyStore` so existing download/decrypt flows still receive `encryptionKeyBase64`
- repository saves of group keys write actual group key material to `SecureKeyStore` and raw SQL stores only an opaque reference
- repository reads hydrate group key material for latest, generation-specific, startup mirror, and pruning flows
- legacy SQL rows with plaintext media/group key values are migrated by an idempotent post-open secure-storage scrub
- direct tests inspect raw `media_attachments` and `group_keys` rows and prove plaintext-equivalent values are absent after repository writes and after legacy scrub
- fresh install/full-chain schema expectations remain green; no database version bump is introduced unless the implementation truly changes schema
- source matrix DB-006, `test-inventory.md`, this plan, and the breakdown cite concrete file/test evidence before DB-006 is marked `Covered`

## Source Of Truth

- Primary source row: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, DB-006.
- Current prerequisite ledger: row 56 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Existing blocker record: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-DB-006-plan.md`.
- DB workflow source: `flutter-sqlite-migrations-and-repositories` repo DB map.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

Current code and focused tests beat stale prose if they disagree.

## Session Classification

`implementation-ready`.

This is a host-only code-and-test prerequisite. The missing evidence is local secure storage plus table inspection, not real relay/device behavior.

## Exact Problem Statement

DB-006 requires secret keys, media keys, and recovery material to stay out of ordinary message/media/key tables. Identity private key, mnemonic, ML-KEM secret key, and SQLCipher DB-key handling already have positive evidence. The remaining gap is that group media per-object keys are persisted directly in `media_attachments.encryption_key_base64`, and group key material is persisted directly in `group_keys.encrypted_key`. SQLCipher encryption alone does not satisfy the row because the row asks whether ordinary tables contain plaintext-equivalent secret material.

## Files And Repos To Inspect Next

- `lib/core/secure_storage/secure_key_store.dart`
- `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`
- likely new secure-storage helper for group media/group key secure names and legacy scrub
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/features/groups/domain/models/group_key_info.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/main.dart`
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`

## Existing Tests Covering This Area

- Identity secure-storage evidence is recorded in the DB-006 plan and remains out of scope unless broken.
- `media_attachments_db_helpers_test.dart` currently proves the raw helper can store `encryption_key_base64`; this is a lower-level helper behavior and not enough for production closure.
- `group_keys_db_helpers_test.dart` currently proves the raw helper can store values in `group_keys.encrypted_key`; this is a lower-level helper behavior and not enough for production closure.
- `media_attachment_repository_impl_test.dart` and `group_repository_impl_test.dart` are the right production-facing tests to prove secure-store wrapping and hydration.
- `full_migration_chain_test.dart` is the schema guard; because this plan should not need a schema change, it must stay green without a new migration number.

## Regression/Tests To Add First

- Add media repository tests:
  - `PREREQ-SECRET-STORAGE-WRAPPING saveAttachment stores media key in secure storage and only a reference in SQL`
  - `PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage hydrates media key from secure storage`
  - `PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessages hydrates secure media keys`
- Add group repository tests:
  - `PREREQ-SECRET-STORAGE-WRAPPING saveKey stores group key material in secure storage and only a reference in SQL`
  - `PREREQ-SECRET-STORAGE-WRAPPING getLatestKey and getKeyByGeneration hydrate group key material`
  - `PREREQ-SECRET-STORAGE-WRAPPING mirrorAllKeysToSecureStore writes hydrated material, not SQL reference text`
- Add legacy scrub tests:
  - plaintext media key row is moved to secure storage and SQL becomes a reference
  - plaintext group key row is moved to secure storage and SQL becomes a reference
  - rerunning the scrub is idempotent and does not overwrite existing secure-store material incorrectly
- Add or update full-chain proof only if implementation changes migration wiring; otherwise run the existing fresh-install path to prove schema stability.

## Step-By-Step Implementation Plan

1. Add a small secure-storage helper for deterministic key names and reference values:
   - media attachment key name by attachment id
   - group key material name by group id plus generation
   - reference encoding/decoding, using a non-secret prefix such as `secure:`
2. Add an idempotent post-open scrub function that reads legacy SQL values, writes actual key material to `SecureKeyStore`, and updates SQL values to references for `media_attachments.encryption_key_base64` and `group_keys.encrypted_key`.
3. Update `MediaAttachmentRepositoryImpl` with optional `SecureKeyStore` injection. On save, store non-empty `encryptionKeyBase64` in secure storage and persist a reference; on read, hydrate references back to the model field.
4. Update `GroupRepositoryImpl` with optional primary group key secure store injection. On save, store actual `GroupKeyInfo.encryptedKey` in secure storage and persist a reference; on read, hydrate references before returning models. Make pruning and shared-push mirroring operate on hydrated keys.
5. Wire the scrub and primary secure-store injection in `main.dart`. Keep `pushSharedKeyStore` as the shared push mirror only, not the primary owner.
6. Add the focused tests above. Directly inspect raw SQL rows in repository and scrub tests to prove plaintext-equivalent values are absent.
7. Run the required direct tests and named gates.
8. Update DB-006 source docs to `Covered` only after QA accepts. Do not close DB-012, EK-012, or media wire/privacy rows from this storage-only evidence.

## Risks And Edge Cases

- Legacy plaintext SQL rows must be scrubbed before startup mirroring writes shared push keys; otherwise shared push storage could receive reference text instead of actual material.
- Secure-store read failures or missing values must not silently convert a secret-bearing model into an apparently valid but undecryptable key. Tests should assert hydrated values when secure store contains material; missing-material behavior can remain a normal missing-key/decryption failure path.
- Repository tests that construct the repository without a secure store may keep legacy raw behavior for existing unit coverage, but production `main.dart` must pass the store.
- Raw helper tests can keep proving helper-level SQL behavior, but DB-006 closure must rely on production repository and scrub evidence.
- Do not delete columns in this session; many schema and model paths expect the columns to exist.

## Exact Tests And Gates To Run

- `flutter test --no-pub test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'`
- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'`
- legacy scrub test command, using the file created by the Executor
- `flutter test --no-pub test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `flutter test --no-pub test/core/database/helpers/group_keys_db_helpers_test.dart`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path'`
- targeted `dart analyze` over touched Dart files
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Known-Failure Interpretation

- Broad `dart analyze lib/main.dart` has unrelated pre-existing diagnostics, including a `GroupListWired` constructor mismatch involving `groupPendingKeyRepairRepository` and unrelated broad-main unused/style diagnostics. Use targeted analyzer for touched files and document any pre-existing unrelated diagnostics.
- Raw helper tests may still demonstrate that helpers can write arbitrary rows when called directly. That is not a blocker if production repositories and the startup scrub remove plaintext-equivalent material from ordinary SQL rows.

## Done Criteria

- Production `main.dart` wires secure-store-backed media and group repositories plus the post-open scrub.
- Raw SQL inspection tests prove `media_attachments.encryption_key_base64` and `group_keys.encrypted_key` contain references, not the original key material, after production repository writes and legacy scrub.
- Repository load tests prove existing application consumers still receive hydrated media and group key material.
- Required focused tests, groups gate, completeness-check, analyzer, and diff hygiene pass or have documented pre-existing unrelated caveats.
- DB-006 source matrix, `test-inventory.md`, this plan, and breakdown ledger are updated to `Covered` only after final QA accepts.

## Scope Guard

- Do not redesign group media encryption or group key cryptography.
- Do not change wire payload shapes, relay storage, invite payloads, push payloads, or UI copy.
- Do not remove existing SQL columns in this session.
- Do not claim DB-012, EK-012, LP-007, relay-visible privacy, or packet-capture closure from local SQL secure-reference evidence.
- Do not treat SQLCipher encryption alone as satisfying DB-006.

## Accepted Differences / Intentionally Out Of Scope

- Secure-store references can remain in existing SQL columns to avoid a table rebuild. The closure bar is absence of plaintext-equivalent key material from ordinary SQL rows, not physical column removal.
- Raw DB helpers can remain low-level row writers if production repositories and startup scrub own secure wrapping.
- Orphan cleanup for secure-store media keys after delete is desirable but not required for DB-006 closure unless direct tests expose visible stale-state behavior.

## Dependency Impact

- DB-006 can move to `Covered` if this plan closes.
- No dependent Partial row should close from this prerequisite.
- Remaining unresolved rows after this prerequisite, if accepted, should be `EK-004`, `EK-012`, `DB-012`, `EC-006`, and `EC-007`.

## Arbiter Decision

`execution-ready`.

The plan is narrow enough to implement safely. It uses existing secure-storage infrastructure, keeps database schema stable unless implementation proves otherwise, preserves repository hydration for existing callers, and requires direct raw-table inspection before DB-006 can close.

## Execution Progress

| timestamp | role | files inspected or touched | command/result | decision/blocker | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T21:44:55+02:00 | Controller | Plan file, dirty worktree status, skill contract | `git status --short` showed a heavily dirty worktree with unrelated group-chat changes; `rg '## Execution Progress' ...` found no existing section; `command -v codex` returned `/opt/homebrew/bin/codex` | Contract extracted. Scope remains DB-006-only: secure-store references for media keys and group keys, production wiring, idempotent scrub, no source matrix/doc closure by this executor. | Spawn Executor with bounded plan prompt. |
| 2026-05-01T21:45:30+02:00 | Controller | Child-agent launch command | `codex exec ... -a never ...` exited 2 because this CLI's `exec` subcommand does not accept `-a` | Spawn attempt did not materialize or touch files. | Relaunch Executor using supported no-prompt option. |
| 2026-05-01T21:46:49+02:00 | Executor | Plan file; dirty worktree; `secure_key_store.dart`; media/group repository impls; media/group key models and DB helpers; `main.dart`; focused repo tests | `git status --short` showed heavy unrelated edits; owner path status showed only `lib/main.dart` dirty among likely owner files before executor edits. Read plan and owner files. | Proceed with DB-006-only implementation: secure reference helper, legacy scrub, repository hydration, production wiring, focused tests. Preserve existing `main.dart` migration/repository changes. | Patch secure reference helper and repositories. |
| 2026-05-01T21:51:23+02:00 | Executor | Added `secret_storage_references.dart`, `legacy_group_secret_storage_scrub.dart`; touched media/group repositories, `main.dart`, focused media/group/scrub tests | `dart format ...` completed successfully on touched Dart files. | Secure-reference writes, read hydration, production injection, and legacy scrub tests are in place. | Run focused PREREQ tests. |
| 2026-05-01T21:52:02+02:00 | Executor | Focused media repo, group repo, and legacy scrub tests | `flutter test --no-pub test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` passed; `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` passed; `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` passed. | Direct DB-006 behavior evidence is green. | Run helper tests, migration-chain guard, analyzer, named gates, and diff hygiene as feasible. |
| 2026-05-01T21:55:19+02:00 | Executor | Helper tests, migration-chain guard, analyzer, named gates, diff hygiene | `flutter test --no-pub test/core/database/helpers/media_attachments_db_helpers_test.dart` passed; `flutter test --no-pub test/core/database/helpers/group_keys_db_helpers_test.dart` passed; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path'` passed; targeted analyzer over new/repository/test files passed; analyzer including `lib/main.dart` exited 0 with one unrelated pre-existing style info at line 1189; `./scripts/run_test_gates.sh groups` passed; `./scripts/run_test_gates.sh completeness-check` passed; `git diff --check` passed. | Required executor evidence is green. No source matrix docs were modified. | Final review and handoff. |
| 2026-05-01T21:55:52+02:00 | Executor | Final touched-path status and code review | `git status --short -- <executor paths>` shows only the DB-006 implementation/test files plus the plan file under executor scope, with `lib/main.dart` already sharing unrelated pre-existing edits. | Executor verdict: implementation complete and ready for QA. No blockers. | QA reviewer should inspect diff and decide DB-006 doc closure; executor did not edit source matrix docs. |
| 2026-05-01T21:57:39+02:00 | Controller | Plan execution log, executor summary, dirty worktree status | Preparing spawned QA review against the DB-006 implementation paths only. | Reviewer must verify secure-reference writes/hydration/scrub behavior and confirm no out-of-scope matrix closure. | Spawn QA reviewer. |
| 2026-05-01T22:01:24+02:00 | QA Reviewer | Secure reference helper, legacy scrub, media/group repositories, `main.dart`, focused PREREQ tests, DB-006 source row status | QA verdict: `PASS`, no blocking findings. Reran `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` (`+3`, passed); `flutter test --no-pub test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` (`+3`, passed); `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` (`+3`, passed); `git diff --check` passed. | QA verified media/group SQL writes use `secure:` references, reads hydrate from `SecureKeyStore`, legacy scrub migrates plaintext-equivalent rows and is idempotent, startup scrub runs before group-key mirroring, production repositories receive the secure store, and DB-006 source closure docs were not moved to `Covered` in this executor scope. | Handoff complete for controller/doc closure. |
| 2026-05-01T22:06:00+02:00 | Controller QA | `media_attachment_repository_impl.dart`; `group_repository_impl.dart`; controller-spawned QA review | Blocking finding: if a stored SQL value is a `secure:` reference but primary secure-store material is missing, repository reads return the reference string as if it were key material; group-key startup mirroring can mirror that reference to shared push storage. | Same-session implementation-owned recovery required. Blocker signature: `PREREQ-SECRET-STORAGE-WRAPPING / missing secure-store material can expose secure references / media_attachment_repository_impl.dart + group_repository_impl.dart + repository tests`. | Spawn fresh fix-pass executor. |
| 2026-05-01T22:08:43+02:00 | Fix-pass Executor | Dirty worktree status; `media_attachment_repository_impl.dart`; `group_repository_impl.dart`; focused media/group repository tests | Inspected the QA blocker and current dirty owner files; no unrelated paths were reverted. | Fix contract narrowed to fail-closed hydration for missing `secure:` material and direct missing-material tests. | Patch owner files and add focused regression tests. |
| 2026-05-01T22:10:29+02:00 | Fix-pass Executor | `media_attachment_repository_impl.dart`; `group_repository_impl.dart`; `media_attachment_repository_impl_test.dart`; `group_repository_impl_test.dart` | `dart format lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart lib/features/groups/domain/repositories/group_repository_impl.dart test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart` completed successfully. | Media hydration now clears `encryption_key_base64` when a `secure:` reference cannot be resolved; group key hydration now returns null for missing referenced material; push mirroring skips unresolved keys and refuses to mirror `secure:` reference text. Added missing-material PREREQ tests for media single/multi reads, group latest/generation lookups, and mirror-all behavior. | Run required focused tests and validation. |
| 2026-05-01T22:11:13+02:00 | Fix-pass Executor | Touched Dart files and plan | `flutter test --no-pub test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` passed (`+5`); `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'` passed (`+5`); `dart analyze lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart lib/features/groups/domain/repositories/group_repository_impl.dart test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart` passed with `No issues found!`; `git diff --check` passed. | Fix-pass verdict: blocker resolved; no blockers found in required validation. | Return handoff with changed paths and exact test results. |
| 2026-05-01T22:11:46+02:00 | Fix-pass Executor | Plan file after execution-progress update | Final `git diff --check` rerun after plan update passed. | Diff hygiene remains clean after recording fix-pass evidence. | Final response. |
| 2026-05-01T22:18:06+02:00 | Final QA | `secret_storage_references.dart`; `legacy_group_secret_storage_scrub.dart`; media/group repositories; `main.dart`; focused PREREQ tests; DB-006 source docs | Final QA accepted with no blocking findings. QA verified secure-reference SQL storage, successful hydration, fail-closed missing-material behavior, startup scrub before group-key mirroring, primary secure-store injection, and no unresolved `secure:` reference mirroring. Reruns covered media PREREQ tests (`+5`), group PREREQ tests (`+5`), legacy scrub PREREQ tests (`+3`), targeted analyzer, and `git diff --check`; executor evidence also covered helper tests, full-chain fresh install, `groups`, and `completeness-check`. | `qa_passed`: DB-006 may move to `Covered`. DB-012 and EK-012 remain out of scope. | Update source matrix, test inventory, and breakdown ledger for DB-006 only; continue to `PREREQ-REMOTE-EVENT-FAMILIES`. |

## Recovery Input

Blocker signature: `PREREQ-SECRET-STORAGE-WRAPPING` / implementation-owned QA blocker / missing primary secure-store material can expose `secure:` references as decryptable key material or mirror those references into shared push storage / owner files `media_attachment_repository_impl.dart`, `group_repository_impl.dart`, `media_attachment_repository_impl_test.dart`, and `group_repository_impl_test.dart`.

Same-session recovery is authorized once for this signature. The repaired contract is that when a SQL value is a secure-store reference and primary secure-store material is absent, repository reads must fail closed instead of returning the reference text as key material, and `mirrorAllKeysToSecureStore` must not write reference text into shared push storage. Add direct tests for media reads, group key lookups, and mirror behavior.

## Final QA Verdict

`accepted / qa_passed`.

DB-006 can close as `Covered` because production media attachment and group key repositories now keep plaintext-equivalent key material out of ordinary SQL rows by writing deterministic `secure:` references and storing the actual material in `SecureKeyStore`; repository reads hydrate when material exists and fail closed when referenced material is missing; startup legacy scrub migrates existing plaintext-equivalent rows before group-key mirroring; and production `main.dart` injects the primary secure store into the relevant repositories.

DB-012 and EK-012 remain out of scope for this prerequisite and must stay `Partial` until their event-family/replay prerequisites close.
