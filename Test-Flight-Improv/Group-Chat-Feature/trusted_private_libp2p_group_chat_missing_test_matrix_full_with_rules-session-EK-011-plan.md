# Session EK-011 Plan - Welcome and Key Package Admission Validation

Status: prerequisite-blocked

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `EK-011` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: move EK-011 to `Covered` only if valid, stale, malformed, wrong-recipient, signed, and weak key-package or welcome-material cases are represented by a first-class repo-owned model and rejected before group admission when invalid.
- Source status at intake: `Partial`.

## Evidence Intake

Current repo behavior:

- The shipped invite path uses signed encrypted direct invites with inline group-key material, not a first-class welcome/key-package object.
- Invite payload parsing rejects missing or contradictory invite policy and invalid join material before group state is materialized.
- Direct invite materialization rolls back group/member/key state on repairable stale welcome or key-package decrypt errors from `group:join`.
- Pending invite acceptance keeps the pending invite retryable and avoids consumed tombstones, mailbox drain, publish, message, group, member, and key state on repairable join-material failures.
- v2 invite handling rejects when the local ML-KEM secret is absent.
- Invite send refuses to encrypt when the recipient ML-KEM public key is missing.

Known current gap:

- There is no repo-owned first-class welcome/key-package model, no key-package validation test surface, no stale/wrong-recipient signed welcome admission proof, and no weak ML-KEM key validation primitive beyond bridge encryption failure paths.
- Direct inline group-key invites and IJ-014 repair-pending behavior are useful adjacent evidence, but they are not full MLS-like welcome/key-package support.

## Scope Guard

Do not mark EK-011 `Covered` from inline group-key invite behavior alone. A complete closure needs an explicit production model or protocol for welcome/key-package material and a validation matrix for valid, stale, malformed, wrong-recipient, signed, and weak packages.

## Direct Evidence

Passed commands:

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'IJ014'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ014'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'returns decryptionFailed when mlKemSecretKey is null and envelope is v2'`
- `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'returns encryptionRequired when recipientMlKemPublicKey is null'`
- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart --plain-name 'policy'`
- `git diff --check`

## Blocker

- Blocker classes:
  - `missing_first_class_welcome_key_package_model`
  - `missing_key_package_validation_before_admission`
  - `missing_wrong_recipient_or_stale_welcome_rejection`
  - `missing_weak_mlkem_key_validation`
  - `missing_signed_welcome_admission_proof`
- EK-011 remains `Partial`; current evidence proves fail-closed inline invite-key and repair-pending behavior, not the row's first-class welcome/key-package admission contract.
