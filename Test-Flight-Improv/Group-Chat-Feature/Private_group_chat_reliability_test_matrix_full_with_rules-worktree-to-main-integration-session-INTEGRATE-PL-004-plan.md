# INTEGRATE-PL-004 Worktree-to-Main Import Contract

Status: accepted

## Scope

- Import only row-owned `PL-004` evidence from the historical worktree into current main.
- Preserve existing dirty accepted/blocked changes for `NW-013`, `NW-014`, `NW-015`, `PL-001`, `PL-002`, and `PL-003`.
- Controller-owned ledger, breakdown, and test-inventory updates are performed only during controller closure, not by the executor.

## Historical Source

- Plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-004-plan.md`
- Row contract: quoted message IDs survive live delivery, offline replay, and remove/re-add boundaries; visible quote parents resolve and missing parents render an unavailable fallback.

## Imported Surfaces

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

## Scope Exclusions

- No PL-007, PL-011, RA, KE, UP, SV, media, reaction, notification, privacy, stress, or broader replay-row imports are claimed by this contract.
- Controller-owned docs and inventory remain for controller verification and closure.

## Closure Evidence

- Imported row-owned selectors for publish/sender quote-id preservation, fake-network live/replay/re-add quote-id preservation, quote-parent widget rendering, and `private_readd_current` `pl004QuoteReaddLiveProof` criteria validation.
- Focused PL-004 application, fake-network, widget, and criteria selectors passed; PL-001/PL-002/PL-003/GE-024/IR-015 preservation selectors passed; scoped format/analyze/diff hygiene passed.
- iOS 26.2 live proof run `1779296325622` passed in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_ALxqho` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Broad `groups` remains red at `+250 -9` on classified non-PL-004 residuals; `completeness-check` remains red at `734/735` on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
