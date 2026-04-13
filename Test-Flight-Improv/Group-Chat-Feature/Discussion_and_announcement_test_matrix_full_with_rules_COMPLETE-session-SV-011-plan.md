# Session Plan: SV-011

## Row Contract

- source row: `SV-011`
- matrix contract: Flow-event names and payload shapes for group timing, recovery, and retry observability are pinned.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows:
  - the shipped group send flow emits stable success and failure event names with the expected detail keys
  - the shipped rejoin and drain flows emit stable batch/group timing and error events with the expected detail keys
  - the shipped failed-message and failed-inbox-store retry owners emit stable start/success/skip/error/timing events with the expected detail keys

## Scope Guard

- keep scope on tests that pin the existing flow-event contract
- prefer strengthening current group application tests over adding new observability features or lifecycle-wide logging
- do not widen into dispatcher overflow, native diagnostics, replay encryption, or unrelated resume sequencing work

## Planned Proof

1. Tighten the existing `send_group_message_use_case_test.dart` flow-event assertions so they cover stable begin/success/timing metadata plus the zero-peer inbox-failure branch.
2. Tighten the existing `rejoin_group_topics_use_case_test.dart` and `drain_group_offline_inbox_use_case_test.dart` regressions so they pin joined/done/error event names and their required detail keys.
3. Tighten the existing retry-owner tests in `retry_failed_group_messages_use_case_test.dart` and `retry_failed_group_inbox_stores_use_case_test.dart` so start/success/skip/error/timing payload shapes are explicit.
4. Run the targeted Dart tests, then update the matrix, inventory, and breakdown if the row-owned observability contract is directly pinned.

## Files Expected

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
