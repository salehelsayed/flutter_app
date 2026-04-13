# Session Plan: RY-014

## Row Contract

- source row: `RY-014`
- matrix contract: Encrypted replay remains seamless for text, replies, image, video, GIF/file, and recorded voice.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows the encrypted replay path preserves quote metadata and the supported media classes through drain and resume

## Scope Guard

- keep scope on encrypted replay parity, not relay opacity or membership cutoffs
- prefer direct replay-path assertions over adding new rendering features
- use the real drain and resume surfaces instead of inventing a parallel harness

## Executed Proof

1. `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` now proves encrypted replay preserves `quotedMessageId` plus image, video, GIF, file, and audio attachments through the real drain path.
2. `test/features/groups/integration/group_resume_recovery_test.dart` keeps missed announcement replay, voice delivery, and post-rotation delivery readable after resume on the same replay contract.
3. The replay batch passed in the current session with the mixed-media encrypted drain regression included.

## Files Expected

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

