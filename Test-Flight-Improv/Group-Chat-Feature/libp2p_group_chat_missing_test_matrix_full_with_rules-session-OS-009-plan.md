# OS-009 Undecryptable Epoch Gap Placeholder Plan

## Session Intake

- breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row: `OS-009 | Irrecoverable epoch gap creates safe undecryptable placeholders`
- disposition: `needs_code_and_tests`
- execution classification: `implementation-ready`
- local plan fallback: used after the spawned planning attempt no-progressed without leaving a reusable plan

## Current Evidence Hypothesis

Current adjacent behavior fails closed but does not satisfy OS-009:

- mixed known-epoch encrypted replay stores rows under the original key epoch
- unknown future-epoch encrypted replay is skipped before decrypt with `GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED`
- Go PubSub rejects unknown future epochs before live delivery

The missing row behavior is a durable, safe, user-visible placeholder for an irrecoverable/missing epoch gap. Current skip-only behavior avoids plaintext guesswork but leaves no conversation row.

## Scope

Implement the smallest durable placeholder path for replay decode failures caused by missing group replay keys.

Likely owners:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/models/group_message.dart`
- message repository/helpers only if the existing model cannot represent the placeholder safely
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- a narrow presentation test only if the existing conversation UI would hide or unsafe-render the placeholder

## Scope Guard

- Do not implement key repair, direct peer sync, anti-entropy, or multi-peer gap repair.
- Do not treat arbitrary decode failures as plaintext.
- Do not store encrypted ciphertext as visible text.
- Do not broaden into OS-006 gap repair, OS-012 real bridge/GossipSub partition proof, EK-005 future-epoch queue repair, or MD media quarantine rows.
- Preserve existing fail-closed behavior for malformed payloads that cannot identify a message or epoch safely.

## Acceptance Criteria

Accept as `Covered` only if direct tests prove:

- future/missing epoch encrypted replay creates a durable incoming placeholder row when the message id can be safely identified from the replay envelope
- placeholder text is safe, generic, and does not expose ciphertext or guessed plaintext
- placeholder row records the missing key epoch
- no `group.decrypt` call is attempted when the key is absent
- duplicate replays for the same missing message id do not create duplicate placeholders
- known-epoch replay still decrypts and persists normally
- UI/presentation surfaces the safe placeholder text without media rendering or unsafe preview

Block or keep Partial if the repo cannot identify message id/epoch from failed encrypted replay envelopes without changing the replay format.

## Evidence Commands

- `rg -n "undecryptable|placeholder|future epoch|unknown future|key gap|epoch gap|missing key|DECODE_SKIPPED" lib/features/groups test/features/groups go-mknoon/node`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "future epoch encrypted replay before key update is rejected without fallback persistence"`
- new OS-009 focused drain placeholder tests
- narrow presentation test for safe placeholder rendering if needed
- `cd go-mknoon && go test ./node -run 'RejectsUnknownFutureEpoch|WrongKeyEpoch' -v`
- `printenv FLUTTER_DEVICE_ID`
- `printenv MKNOON_RELAY_ADDRESSES`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Session Gates

- focused drain placeholder tests
- focused presentation rendering test if changed
- Go unknown/wrong epoch validator slice
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Done Criteria

- OS-009 has a truthful implementation verdict.
- Source matrix and `test-inventory.md` record Covered only with direct placeholder evidence.
- Session breakdown ledger records OS-009 truthfully and includes closure evidence.

## Execution Evidence

- Added `groupUndecryptablePlaceholderText` and a missing-replay-key placeholder path in `drain_group_offline_inbox_use_case.dart`.
- The drain path now catches missing group replay key failures, extracts the replay envelope `messageId` and `keyEpoch`, and saves one incoming `undecryptable` `GroupMessage` with generic safe text instead of calling `group.decrypt`, displaying ciphertext, guessing plaintext, or dropping all UI evidence.
- Existing conflict-replace message storage and an explicit existing-message check dedupe repeated missing-key replay by `messageId`; a later successful replay can replace the placeholder with the real message under the same id.
- Known-epoch replay behavior is preserved.
- Added `renders undecryptable epoch placeholders as safe text` in `group_conversation_screen_test.dart`.
- `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset, so live device/relay proof remains supplemental and fixture-blocked.

## Verification

- `rg -n "undecryptable|placeholder|future epoch|unknown future|key gap|epoch gap|missing key|DECODE_SKIPPED" lib/features/groups test/features/groups go-mknoon/node`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "future epoch encrypted replay creates one undecryptable placeholder without decrypting"` passed.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "drains mixed epoch encrypted replay out of order without rewriting epochs"` passed.
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "renders undecryptable epoch placeholders as safe text"` passed.
- `cd go-mknoon && go test ./node -run 'RejectsUnknownFutureEpoch|WrongKeyEpoch' -v` passed.

## Execution Verdict

`accepted`

OS-009 is Covered by direct code and tests. Missing replay-key epoch gaps now produce a safe visible placeholder row with the original replay message id, missing key epoch, and generic text; duplicate replay does not create duplicate rows; no decrypt is attempted without the key; and known-epoch replay still decrypts and persists normally. This does not implement EK-005 queue-and-repair semantics, which remains separately Partial.
