# Libp2p Group Chat Policy-Needed Matrix

This decision-focused matrix contains the rows from the source matrix that remain `Contract-undefined` after the 2026-04-05 rollout.

Do not run implementation rollout directly from this doc until the product rule is explicitly decided for each row.

- These rows are not marked unsupported; they are unresolved because the current repo does not define the contract precisely enough to implement or verify them honestly.
- After the policy is decided, move the resolved rows into an execution matrix and then run `$test-matrix-row-decomposer` and `$implementation-session-pipeline-orchestrator` on that execution doc.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Included rows: 1

## Filtering Rule

- Rows are copied verbatim from the source matrix, including preconditions, steps, expected result, coverage columns, and notes.
- Only the status-filtered rows are included here; row wording and ordering stay aligned with the source matrix.

`UX-013` (Multi-device state convergence) was reopened to `Partial` on
2026-06-16. Its *device-local* contract is now defined and honest, but the
**shared-across-devices** half remains a pending product/security decision:

| ID | Journey | Undecided contract | Decision needed |
|---|---|---|---|
| UX-013 | Multi-device state convergence | Whether/how a freshly restored second device gains real group convergence (state + key access). | (1) Build real second-device convergence at all, or keep device-local permanently? (2) If built, the restore-time key-continuity trade-off: **B1a** (back up the ML-KEM secret with the mnemonic — simpler, weakens forward secrecy) vs **B1b** (per-device keys + re-distribution + sibling-device admission — forward-secret, larger). (3) Trust gate for sibling-device admission (admin-signed device-add transition vs safety-number prompt). Specified in `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/12-P2-multi-device-honesty.md` Part B; gated behind `kMultiDeviceSyncEnabled`. |

Once the Part B contract is decided and device-matrix verified, move UX-013 to an
execution matrix and re-close it with the policy contract test green.
