# Libp2p Group Chat Policy-Needed Matrix

This decision-focused matrix contains the rows from the source matrix that remain `Contract-undefined` after the 2026-04-04 rollout.

Do not run implementation rollout directly from this doc until the product rule is explicitly decided for each row.

- These rows are not marked unsupported; they are unresolved because the current repo does not define the contract precisely enough to implement or verify them honestly.
- After the policy is decided, move the resolved rows into an execution matrix and then run `$test-matrix-row-decomposer` and `$implementation-session-pipeline-orchestrator` on that execution doc.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Included rows: 3

## Filtering Rule

- Rows are copied verbatim from the source matrix, including preconditions, steps, expected result, coverage columns, and notes.
- Only the status-filtered rows are included here; row wording and ordering stay aligned with the source matrix.

## Metadata, Notifications, and Optional Feature Coverage

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-Party E2E (3 simulators) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UX-008 | Store-and-forward expiry / retention boundary | Offline retention/TTL exists. | 1. Keep C offline past the retention boundary. 2. Send messages. 3. C reconnects. | Behavior matches policy: expired messages are unavailable with clear UX, and newer retained messages sync normally. | P2 | Recommended | Required | N/A | Required | Recommended | Contract-undefined on 2026-04-04: store-and-forward replay exists, but the current repo does not define or prove a retention or TTL expiry boundary for group messages. |
| UX-009 | Max group size limit | A configured or product max group size exists. | 1. Add members until limit is reached. 2. Try to add one more. | Add beyond limit fails cleanly with clear feedback; existing group remains healthy. | P2 | Required | Required | N/A | N/A | N/A | Contract-undefined on 2026-04-04: the repo documents scale targets and profiling ranges, not a hard max-group-size enforcement rule, so this row remains unscoped rather than covered. |
| UX-013 | Multi-device state convergence | A user can be signed in on multiple devices. | 1. Use two devices for the same user. 2. Apply membership, mute, and message changes. | Both devices converge to the same group state, notifications, and unread counters per product rule. | P2 | Required | Required | N/A | Recommended | Recommended | Contract-undefined on 2026-04-04: current repo proof is multi-peer convergence only, with no same-user multi-device contract or regression to close this row honestly. |
