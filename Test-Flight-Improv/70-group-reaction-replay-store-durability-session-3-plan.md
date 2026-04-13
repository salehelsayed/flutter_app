# 70 Session 3 Plan: Close Maintained Group Docs for Report 70

## Final Verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-13`
- Why:
  - the maintained group audit, matrix, and inventory docs no longer describe
    sender-side reaction replay durability as a residual best-effort gap
  - `RX-006` and `RY-016` notes now cite the landed sender-owned replay retry
    evidence without overclaiming beyond the actual add/remove durability
    contract
  - the doc-70 breakdown now records a final closed verdict backed by same-day
    code, tests, and gate evidence

## Landed Scope

- refresh the maintained group audit so it stops listing sender-side reaction
  replay durability as an open reliability concern
- refresh the full discussion/announcement matrix residual section and the
  `RX-006` / `RY-016` row notes to reference the landed reaction retry owner
- refresh the test inventory residual section and accepted-row notes so they
  match the new proof set
- persist the final closed verdict in the reusable doc-70 breakdown artifact

Out of scope for this session:

- any new product or transport work beyond the already landed Report `70`
  contract
- unrelated matrix cleanup

## Files

- `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Verification

- closure reuses the same-day accepted code and proof from Sessions `1` and `2`
- governing evidence carried into closure:
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "resume retry replays failed reaction add/remove stores and converges to the final removed state"`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`

## Scope Guard

- do not widen into other reaction UX or group recovery rows
- do not reopen Sessions `1` or `2` unless a real regression appears in the
  landed code or proof
