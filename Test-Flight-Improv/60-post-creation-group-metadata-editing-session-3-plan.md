# 60 Session 3 Plan: Metadata Recovery Proof and Closure Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add the missing row-closing regression(s) for offline metadata convergence and
  repeated metadata edit ordering if the current repo proof is still thinner
  than the matrix/doc closure bar
- close `MR-023`, `SC-002`, `UX-002`, and `UX-003` in the maintained audit and
  matrix docs using only evidence that is now landed in code/tests
- update the metadata feature summaries so they no longer describe post-creation
  rename/photo/description editing as unsupported scope
- persist the final doc-60 breakdown verdict once code, tests, and maintained
  docs all agree

Out of scope for this session:

- any new product surface beyond bounded evidence gaps
- notification mute, invite decision, or dissolve work from later docs
- speculative protocol redesign that is not required by the existing metadata
  contract

### Closure bar

Session `3` is done only when:

- the repo has truthful proof that offline peers converge to the final metadata
  state after repeated post-creation edits
- the existing unauthorized/stale metadata rejection proof remains explicit and
  cited in the maintained docs
- `11-group-discussion-use-case-audit.md`,
  `09-network-group-messaging.md`,
  `libp2p_group_chat_test_matrix_full_with_rules.md`, and
  `libp2p_group_chat_matrix_features_did_not_exist.md`
  all stop describing post-creation metadata editing as unsupported
- the `groups` gate passes after any added proof
- the doc-60 breakdown can truthfully record a finished verdict

### Source of truth

- active session contract:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- audit truth:
  `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- matrix truth:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  and
  `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- network summary:
  `Test-Flight-Improv/09-network-group-messaging.md`
- landed session `1` and `2` code/tests win over stale prose on disagreement

### Exact problem statement

The metadata mutation contract and shipped editing surface are now landed, but
doc `60` is not finished until the long-lived audit/matrix docs stop claiming
that rename/photo/description editing is unsupported and the repo has explicit
proof for offline final-state convergence under repeated metadata edits.

### Files and repos to inspect next

Proof files:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Closure docs:

- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`

### Existing proof already in repo

- `group_message_listener_test.dart` already proves authenticated
  `group_metadata_updated` handling, unauthorized rejection, avatar-path
  persistence, and stale-event rollback protection after restart
- session `2` presentation tests already prove the admin-only edit affordance,
  group-list metadata refresh, and conversation-header refresh after returning
  from group info
- `./scripts/run_test_gates.sh groups` is green after the shipped metadata UI
  landed

### Likely missing proof to add

- one offline/reconnect regression proving a peer that misses repeated metadata
  edits converges to the final metadata state rather than the last replayed
  page/order artifact

### Step-by-step implementation plan

1. Re-read the current metadata listener and resume-recovery tests to confirm
   exactly which row-closing claim is still missing.
2. If offline repeated-edit convergence is not already explicitly covered, add
   one bounded regression in
   `test/features/groups/integration/group_resume_recovery_test.dart`.
3. Run the direct proof tests needed for the new or reused evidence.
4. Run `./scripts/run_test_gates.sh groups`.
5. Update the maintained audit/network/matrix docs to replace unsupported
   wording with landed evidence and exact citations.
6. Remove `MR-023`, `SC-002`, `UX-002`, and `UX-003` from the unsupported-only
   doc if the matrix now closes them.
7. Mark the doc-60 breakdown finished only after code/test/doc truth matches.

### Risks and edge cases

- do not over-claim avatar convergence beyond what the landed tests actually
  prove; use combined evidence where unit proof and integration proof cover
  different seams
- do not reopen session `2` surface work unless the recovery proof reveals a
  real shipped bug
- keep doc wording aligned with exact tests rather than broad aspirational
  statements

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- treat unrelated pre-existing failures outside group metadata, offline recovery,
  or closure docs as known only if they reproduce on unchanged code
- do not waive new failures in the listener, recovery, or groups gate paths

### Done criteria

- the missing metadata recovery/order proof is landed or truthfully confirmed as
  already covered
- the maintained docs now record metadata editing as shipped behavior with exact
  evidence
- the unsupported-features doc no longer lists the closed metadata rows
- the `groups` gate passes
- the doc-60 breakdown records a finished closed verdict

### Scope guard

- do not widen into mute controls, invite decisions, or dissolve work
- do not redesign matrix structure beyond the row updates needed for truth
- do not invent new metadata semantics beyond the landed session `1` contract

## Structural blockers remaining

- none

## Exact docs/files used as evidence

- `Test-Flight-Improv/60-post-creation-group-metadata-editing-session-breakdown.md`
- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

## Why the plan is safe to implement now

- the repo already has the metadata mutation contract and shipped UI, so the
  remaining work is bounded to proof closure and doc truth
- the plan names one likely missing integration seam instead of reopening the
  whole feature
- the required gate is explicit and already green on the current feature slice
