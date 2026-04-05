# Libp2p Group Chat Policy-Needed Matrix

This decision-focused matrix contains the rows from the source matrix that remain `Contract-undefined` after the 2026-04-05 rollout.

Do not run implementation rollout directly from this doc until the product rule is explicitly decided for each row.

- These rows are not marked unsupported; they are unresolved because the current repo does not define the contract precisely enough to implement or verify them honestly.
- After the policy is decided, move the resolved rows into an execution matrix and then run `$test-matrix-row-decomposer` and `$implementation-session-pipeline-orchestrator` on that execution doc.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Included rows: 0

## Filtering Rule

- Rows are copied verbatim from the source matrix, including preconditions, steps, expected result, coverage columns, and notes.
- Only the status-filtered rows are included here; row wording and ordering stay aligned with the source matrix.

No matrix rows remain in explicit `Contract-undefined` status after the
`2026-04-05` closure of `UX-013`.
