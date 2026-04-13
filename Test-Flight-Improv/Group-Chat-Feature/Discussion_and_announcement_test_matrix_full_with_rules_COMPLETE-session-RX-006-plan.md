# Session Plan: RX-006

## Row Contract

- source row: `RX-006`
- matrix contract: Live, replayed, and post-rotation reactions remain truthful after resume/rejoin.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local tests directly prove reaction truth across:
  - resume/rejoin with replayed reaction delivery
  - live-plus-replay dedupe on the same reaction after resume
  - post-rotation reaction recovery on a post-rotation message

## Scope Guard

- tests only
- do not broaden into new reaction UI work, invite-accept timing work, or unrelated recovery gaps
- do not accept the row unless new proof is concrete and row-owned

## Planned Proof

1. Add an integration regression showing a receiver that already got a live reaction can resume/rejoin, drain the same reaction from inbox replay, and still retain one truthful stored reaction.
2. Add an integration regression showing a receiver can rejoin after going offline, drain a reaction for a post-rotation message, and retain the truthful reaction on the rotated message.
3. Run the targeted recovery integration tests.

## Files Expected

- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
