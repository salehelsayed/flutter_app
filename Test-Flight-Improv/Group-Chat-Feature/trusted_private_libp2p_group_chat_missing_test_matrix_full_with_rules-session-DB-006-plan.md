# DB-006 Session Plan - Plaintext secret keys are excluded from ordinary message tables

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:14:00+02:00 | Local planner completed | DB-006 source matrix row; `test-inventory.md`; `lib/core/database/migrations/004_nullify_secret_columns.dart`; `lib/core/database/migrations/005_secret_null_checks.dart`; `lib/core/database/migrations/059_media_attachment_encryption_columns.dart`; `lib/core/database/helpers/media_attachments_db_helpers.dart`; `lib/core/database/helpers/group_keys_db_helpers.dart`; `lib/features/groups/domain/repositories/group_repository_impl.dart`; focused identity, media, group-key, and migration tests | DB-006 cannot close because identity secrets are protected, but group media object keys and group keys are still persisted in ordinary SQL columns. The current evidence is enough to move the source row from `Open` to `Partial`, not `Covered`. | Persist DB-006 as `Partial`/prerequisite-blocked and record the exact blockers. |

## real scope

DB-006 asks that secret keys, media keys, and recovery material stay out of ordinary database tables. Current repo evidence satisfies identity secret handling, but does not satisfy group media keys or group key material.

## closure bar

DB-006 can move to `Covered` only when:

- identity private key, mnemonic, and ML-KEM secret key remain nullable and CHECK-constrained in SQL after secure-storage migration
- the SQLCipher DB encryption key is stored in secure storage
- group media per-object keys are not stored as plaintext-equivalent values in ordinary `media_attachments` rows
- group key material stored in `group_keys.encrypted_key` is proven wrapped/non-plaintext or moved to an approved secure-storage owner
- focused tests inspect group/message/media/event tables and prove no plaintext-equivalent secret key material is present

## session classification

`prerequisite-blocked`. Existing tests prove both the passing identity side and the blocking media/group-key SQL state.

## Device/Relay Proof Profile

- Profile for this session: host-only database evidence.
- Live device/relay proof is not relevant until the local secret storage model is corrected.

## files touched

- closure docs only

## evidence checked

- Identity secret migrations and helpers reject non-null identity secrets after secure-storage migration.
- `encrypted_db_opener` generates and stores the SQLCipher DB encryption key through `SecureKeyStore`.
- `media_attachments.encryption_key_base64` exists and tests assert a direct value such as `key-1` remains in ordinary SQL rows.
- `group_keys.encrypted_key` exists and tests assert direct fixture values such as `base64-key-gen1`, `key-gen2`, and `key-gen3` remain in ordinary SQL rows.
- `GroupRepositoryImpl.mirrorAllKeysToSecureStore` mirrors existing SQL keys to secure storage, but does not remove the SQL copy or prove it is wrapped before storage.

## exact tests and gates run

- `flutter test --no-pub test/core/database/migrations/004_nullify_secret_columns_test.dart test/core/database/migrations/005_secret_null_checks_test.dart test/core/database/helpers/identity_db_helpers_test.dart test/core/database/encrypted_db_opener_test.dart` passed (`+26`).
- `flutter test --no-pub test/core/database/migrations/059_media_attachment_encryption_columns_test.dart test/core/database/helpers/media_attachments_db_helpers_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart` passed (`+24`) while proving the media/group-key SQL blockers.
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path creates all tables with correct schema'` passed (`+1`).
- `git diff --check` must pass after closure docs.

## blocker class

- `missing_first_class_secure_group_media_key_storage_owner`
- `plaintext_media_attachment_key_column`
- `unproven_group_key_wrapping_for_sql_group_keys`

## done criteria for this blocked session

- Source matrix DB-006 moves from `Open` to `Partial` with explicit blockers and evidence.
- `test-inventory.md` DB-006 crosswalk records the fresh 2026-05-01 evidence.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and counts record DB-006 as `prerequisite-blocked`.
- No `Covered` or accepted DB-006 claim is made.

## scope guard

Do not treat SQLCipher database encryption alone as proof that ordinary message/media/key tables exclude plaintext-equivalent secrets. Future closure needs a row-owned secure storage or wrapping design for group media keys and group key material, plus direct table-inspection tests.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:15:00+02:00 | Local evidence auditor completed | DB-006 source row; focused identity secret tests; media encryption-column tests; media helper tests; group key helper tests; full migration-chain fresh schema check; secure-store mirror evidence | Blocked. Identity secret handling is green, but media attachments and group key tables still store plaintext-equivalent key values in ordinary SQL columns. | Persist DB-006 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. DB-006 remains unresolved because group media object keys and group key material still appear in ordinary SQL tables without a proven secure-storage or wrapping owner. The source row may move from `Open` to `Partial` to record concrete identity-secret evidence and the exact remaining blockers, but it cannot move to `Covered`.
