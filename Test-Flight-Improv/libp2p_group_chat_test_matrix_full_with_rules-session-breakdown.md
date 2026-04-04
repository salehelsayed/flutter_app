# Libp2p Group Chat Test Matrix Full With Rules Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Supporting docs:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Decomposition date:
  `2026-04-04`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Row-owned sessions should run through, in breakdown order:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Execute rows in this default order:
  1. `P0` rows in source order
  2. `P1` rows in source order
  3. `P2` rows in source order
- Run `CLOSURE-001` only after the row-owned sessions that remain runnable are resolved.

## Recommended plan count

- `85`
- The smallest safe split is:
  - `84` row-owned sessions keyed directly to source matrix row ids
  - `1` closure-only session for final matrix truth and gate classification
- Row disposition counts:
  - `needs_tests_only`: `45`
  - `needs_code_and_tests`: `4`
  - `needs_repo_evidence`: `18`
  - `repo_external_proof`: `6`
  - `unsupported_product_scope`: `11`
- No shared prerequisite session was added. The breakdown keeps ownership at the row level and pushes shared harness or proof needs down into the affected rows instead of reopening seam buckets.

## Overall closure bar

`libp2p_group_chat_test_matrix_full_with_rules.md` is only closed when all of the following are true at the same time:

- every source row is mapped to exactly one session id or one explicit non-row closure session dependency, with no silent omissions
- every row is truthfully classified as already covered, tests-only, code-plus-tests, repo-external proof, unsupported product scope, or another explicit residual state backed by repo evidence
- unsupported optional rows remain explicit and do not silently create feature-build work
- protocol, ciphertext, raw-injection, or device-lab proof rows are not misrepresented as fully closed by plain Flutter tests
- the source matrix, this breakdown, and any touched closure docs tell the same truthful story about current repo support, current evidence, and real remaining work

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that materially affected row classification:

- The current group gate and direct suites already cover substantial group messaging, membership, invite, rejoin, retry, and key-rotation seams; row-owned proof should reuse those seams rather than inventing a parallel taxonomy.
- `Test-Flight-Improv/09-network-group-messaging.md` records missing feature scope for group avatar/description management and rich admin transfer or dissolution flows.
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md` records no app-layer mute flow, name mostly locked after creation, description editing not surfaced, and roles not richly managed after creation.
- Current remove-member UI evidence shows direct removal affordances but no confirmed confirmation-dialog flow, so `MR-007`, `MR-007B`, and removed-state UX rows stay implementation-facing rather than being auto-closed as already covered.
- Raw protocol bypass, ciphertext, malformed-frame, and signed-event proof rows remain split-boundary work and should not be overclaimed as plain Flutter-only coverage.
- Announcement/admin-only send semantics exist in the current architecture note, so announcement-mode coverage remains repo-owned even though mute and metadata rows do not.

## Matrix row inventory

| Row ID | Priority | Section | Provisional row disposition | Intended session id |
| --- | --- | --- | --- | --- |
| `GM-001` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-001` |
| `GM-002` | `P1` | Core Group Messaging | `needs_tests_only` | `GM-002` |
| `GM-003` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-003` |
| `GM-004` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-004` |
| `GM-005` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-005` |
| `GM-006` | `P1` | Core Group Messaging | `needs_tests_only` | `GM-006` |
| `GM-007` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-007` |
| `GM-008` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-008` |
| `GM-009` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-009` |
| `GM-010` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-010` |
| `GM-011` | `P1` | Core Group Messaging | `needs_tests_only` | `GM-011` |
| `GM-012` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-012` |
| `GM-013` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-013` |
| `GM-014` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-014` |
| `GM-015` | `P0` | Core Group Messaging | `needs_tests_only` | `GM-015` |
| `GM-016` | `P1` | Core Group Messaging | `needs_tests_only` | `GM-016` |
| `MR-001` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-001` |
| `MR-002` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-002` |
| `MR-003` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-003` |
| `MR-004` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-004` |
| `MR-005` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-005` |
| `MR-006` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-006` |
| `MR-007` | `P0` | Membership and Role Control | `needs_code_and_tests` | `MR-007` |
| `MR-007B` | `P1` | Membership and Role Control | `needs_code_and_tests` | `MR-007B` |
| `MR-008` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-008` |
| `MR-009` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-009` |
| `MR-010` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-010` |
| `MR-011` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-011` |
| `MR-012` | `P0` | Membership and Role Control | `needs_code_and_tests` | `MR-012` |
| `MR-013` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-013` |
| `MR-014` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-014` |
| `MR-015` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-015` |
| `MR-016` | `P0` | Membership and Role Control | `unsupported_product_scope` | `MR-016` |
| `MR-017` | `P0` | Membership and Role Control | `unsupported_product_scope` | `MR-017` |
| `MR-018` | `P1` | Membership and Role Control | `unsupported_product_scope` | `MR-018` |
| `MR-019` | `P1` | Membership and Role Control | `unsupported_product_scope` | `MR-019` |
| `MR-020` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-020` |
| `MR-021` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-021` |
| `MR-022` | `P0` | Membership and Role Control | `needs_tests_only` | `MR-022` |
| `MR-023` | `P1` | Membership and Role Control | `unsupported_product_scope` | `MR-023` |
| `MR-024` | `P1` | Membership and Role Control | `needs_tests_only` | `MR-024` |
| `RJ-001` | `P0` | Re-invite and Rejoin | `needs_tests_only` | `RJ-001` |
| `RJ-002` | `P0` | Re-invite and Rejoin | `needs_tests_only` | `RJ-002` |
| `RJ-003` | `P0` | Re-invite and Rejoin | `needs_tests_only` | `RJ-003` |
| `RJ-004` | `P0` | Re-invite and Rejoin | `needs_tests_only` | `RJ-004` |
| `RJ-005` | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-005` |
| `RJ-006` | `P0` | Re-invite and Rejoin | `needs_code_and_tests` | `RJ-006` |
| `RJ-007` | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-007` |
| `RJ-008` | `P0` | Re-invite and Rejoin | `needs_tests_only` | `RJ-008` |
| `RJ-009` | `P0` | Re-invite and Rejoin | `needs_repo_evidence` | `RJ-009` |
| `RJ-010` | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-010` |
| `SC-001` | `P0` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-001` |
| `SC-002` | `P1` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-002` |
| `SC-003` | `P0` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-003` |
| `SC-004` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-004` |
| `SC-005` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-005` |
| `SC-006` | `P0` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-006` |
| `SC-007` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-007` |
| `SC-008` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-008` |
| `SC-009` | `P0` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-009` |
| `SC-010` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-010` |
| `SC-011` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-011` |
| `SC-012` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-012` |
| `SC-013` | `P1` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-013` |
| `SC-014` | `P1` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-014` |
| `SC-015` | `P0` | Security, Correctness, and Convergence | `repo_external_proof` | `SC-015` |
| `SC-016` | `P1` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-016` |
| `SC-017` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-017` |
| `SC-018` | `P0` | Security, Correctness, and Convergence | `needs_repo_evidence` | `SC-018` |
| `UX-001` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_repo_evidence` | `UX-001` |
| `UX-002` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-002` |
| `UX-003` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-003` |
| `UX-004` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-004` |
| `UX-005` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-005` |
| `UX-006` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-006` |
| `UX-007` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_repo_evidence` | `UX-007` |
| `UX-008` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_repo_evidence` | `UX-008` |
| `UX-009` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_repo_evidence` | `UX-009` |
| `UX-010` | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-010` |
| `UX-011` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-011` |
| `UX-012` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-012` |
| `UX-013` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_repo_evidence` | `UX-013` |
| `UX-014` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `unsupported_product_scope` | `UX-014` |
| `UX-015` | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-015` |

## Row traceability rule

- Every source row maps to exactly one row-owned session id with the same id whenever filename-safe.
- No source row was merged into a seam bucket.
- The only non-row session is `CLOSURE-001`, which exists solely for final matrix truth and gate classification after the row-owned sessions finish.
- Later closure work must report final truth per source row, not only per broad subsystem.

## Session ledger

| Session ID | Source row | Priority | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- | --- |
| `GM-001` | `GM-001` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-001-plan.md` | none | `accepted` |
| `GM-003` | `GM-003` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-003-plan.md` | none | `accepted` |
| `GM-004` | `GM-004` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-004-plan.md` | none | `accepted` |
| `GM-005` | `GM-005` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-005-plan.md` | none | `accepted` |
| `GM-007` | `GM-007` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-007-plan.md` | none | `accepted` |
| `GM-008` | `GM-008` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-008-plan.md` | none | `accepted` |
| `GM-009` | `GM-009` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-009-plan.md` | none | `accepted` |
| `GM-010` | `GM-010` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-010-plan.md` | none | `accepted` |
| `GM-012` | `GM-012` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-012-plan.md` | none | `accepted` |
| `GM-013` | `GM-013` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-013-plan.md` | none | `accepted` |
| `GM-014` | `GM-014` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-014-plan.md` | none | `accepted` |
| `GM-015` | `GM-015` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-015-plan.md` | none | `accepted` |
| `MR-001` | `MR-001` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-001-plan.md` | none | `accepted` |
| `MR-002` | `MR-002` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-002-plan.md` | none | `accepted` |
| `MR-005` | `MR-005` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-005-plan.md` | none | `accepted` |
| `MR-006` | `MR-006` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-006-plan.md` | none | `accepted` |
| `MR-007` | `MR-007` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-007-plan.md` | none | `accepted` |
| `MR-009` | `MR-009` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-009-plan.md` | none | `accepted` |
| `MR-010` | `MR-010` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-010-plan.md` | none | `accepted` |
| `MR-011` | `MR-011` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-011-plan.md` | none | `accepted` |
| `MR-012` | `MR-012` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-012-plan.md` | none | `accepted` |
| `MR-014` | `MR-014` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-014-plan.md` | none | `accepted` |
| `MR-015` | `MR-015` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-015-plan.md` | none | `accepted` |
| `MR-016` | `MR-016` | `P0` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-016-plan.md` | none | `stale/already-covered` |
| `MR-017` | `MR-017` | `P0` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-017-plan.md` | none | `stale/already-covered` |
| `MR-020` | `MR-020` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-020-plan.md` | none | `accepted` |
| `MR-022` | `MR-022` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-022-plan.md` | none | `accepted` |
| `RJ-001` | `RJ-001` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-001-plan.md` | none | `accepted` |
| `RJ-002` | `RJ-002` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-002-plan.md` | none | `accepted` |
| `RJ-003` | `RJ-003` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-003-plan.md` | none | `accepted` |
| `RJ-004` | `RJ-004` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-004-plan.md` | none | `accepted` |
| `RJ-006` | `RJ-006` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-006-plan.md` | none | `accepted` |
| `RJ-008` | `RJ-008` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-008-plan.md` | none | `accepted` |
| `RJ-009` | `RJ-009` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-009-plan.md` | none | `accepted` |
| `SC-001` | `SC-001` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-001-plan.md` | none | `accepted` |
| `SC-003` | `SC-003` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-003-plan.md` | none | `accepted` |
| `SC-004` | `SC-004` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-004-plan.md` | none | `accepted` |
| `SC-005` | `SC-005` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-005-plan.md` | none | `accepted` |
| `SC-006` | `SC-006` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-006-plan.md` | none | `accepted` |
| `SC-007` | `SC-007` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-007-plan.md` | none | `accepted` |
| `SC-008` | `SC-008` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-008-plan.md` | none | `accepted` |
| `SC-009` | `SC-009` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-009-plan.md` | none | `accepted` |
| `SC-010` | `SC-010` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-010-plan.md` | none | `accepted` |
| `SC-011` | `SC-011` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-011-plan.md` | none | `accepted` |
| `SC-012` | `SC-012` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-012-plan.md` | none | `accepted` |
| `SC-015` | `SC-015` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-015-plan.md` | none | `accepted` |
| `SC-017` | `SC-017` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-017-plan.md` | none | `accepted` |
| `SC-018` | `SC-018` | `P0` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-018-plan.md` | none | `accepted` |
| `GM-002` | `GM-002` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-002-plan.md` | none | `accepted` |
| `GM-006` | `GM-006` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-006-plan.md` | none | `accepted` |
| `GM-011` | `GM-011` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-011-plan.md` | none | `accepted` |
| `GM-016` | `GM-016` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-016-plan.md` | none | `accepted` |
| `MR-003` | `MR-003` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-003-plan.md` | none | `accepted` |
| `MR-004` | `MR-004` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-004-plan.md` | none | `accepted` |
| `MR-007B` | `MR-007B` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-007B-plan.md` | none | `accepted` |
| `MR-008` | `MR-008` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-008-plan.md` | none | `accepted` |
| `MR-013` | `MR-013` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-013-plan.md` | none | `accepted` |
| `MR-018` | `MR-018` | `P1` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-018-plan.md` | none | `stale/already-covered` |
| `MR-019` | `MR-019` | `P1` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-019-plan.md` | none | `stale/already-covered` |
| `MR-021` | `MR-021` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-021-plan.md` | none | `accepted` |
| `MR-023` | `MR-023` | `P1` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-023-plan.md` | none | `stale/already-covered` |
| `MR-024` | `MR-024` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-024-plan.md` | none | `accepted` |
| `RJ-005` | `RJ-005` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-005-plan.md` | none | `accepted` |
| `RJ-007` | `RJ-007` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-007-plan.md` | none | `accepted` |
| `RJ-010` | `RJ-010` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-010-plan.md` | none | `accepted` |
| `SC-002` | `SC-002` | `P1` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-002-plan.md` | none | `accepted` |
| `SC-013` | `SC-013` | `P1` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-013-plan.md` | none | `accepted` |
| `SC-014` | `SC-014` | `P1` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-014-plan.md` | none | `accepted` |
| `SC-016` | `SC-016` | `P1` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-016-plan.md` | none | `accepted` |
| `UX-001` | `UX-001` | `P1` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-001-plan.md` | none | `accepted` |
| `UX-002` | `UX-002` | `P1` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-002-plan.md` | none | `stale/already-covered` |
| `UX-004` | `UX-004` | `P1` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-004-plan.md` | none | `stale/already-covered` |
| `UX-005` | `UX-005` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-005-plan.md` | none | `accepted` |
| `UX-006` | `UX-006` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-006-plan.md` | none | `accepted` |
| `UX-010` | `UX-010` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-010-plan.md` | none | `accepted` |
| `UX-003` | `UX-003` | `P2` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-003-plan.md` | none | `stale/already-covered` |
| `UX-007` | `UX-007` | `P2` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-007-plan.md` | none | `accepted` |
| `UX-008` | `UX-008` | `P2` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-008-plan.md` | none | `accepted` |
| `UX-009` | `UX-009` | `P2` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-009-plan.md` | none | `accepted` |
| `UX-011` | `UX-011` | `P2` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-011-plan.md` | none | `stale/already-covered` |
| `UX-012` | `UX-012` | `P2` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-012-plan.md` | none | `stale/already-covered` |
| `UX-013` | `UX-013` | `P2` | `evidence-gated` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-013-plan.md` | none | `accepted` |
| `UX-014` | `UX-014` | `P2` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-014-plan.md` | none | `stale/already-covered` |
| `UX-015` | `UX-015` | `P2` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-015-plan.md` | none | `accepted` |
| `CLOSURE-001` | n/a | n/a | `closure-only` | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-CLOSURE-001-plan.md` | all row-owned sessions that remain runnable | `accepted` |

## Session progress notes

- `GM-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    tightened `test/features/groups/integration/group_messaging_smoke_test.dart`
    so the opening smoke scenario now proves shared group id plus aligned
    member/admin state across A/B/C after the `member_added` sync step
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`,
    `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`,
    `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart`,
    `./scripts/run_test_gates.sh groups`,
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - blocker note:
    none; an earlier baseline attempt failed only because multiple devices were
    connected without an explicit device id, and the pinned-device rerun passed

- `GM-003`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing opening scenario in
    `test/features/groups/integration/group_messaging_smoke_test.dart` already
    proves A/B/C are online in the same group, B and C receive A's message,
    and A retains the local successful outgoing copy; the direct sender seam is
    separately covered by
    `test/features/groups/application/send_group_message_use_case_test.dart`
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`,
    `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
  - blocker note:
    none; this was an acceptance-only session with no GM-003-specific code or
    test delta beyond the already-validated GM-001 smoke-test change, so no
    named gate rerun was required

- `GM-004`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing opening scenario in
    `test/features/groups/integration/group_messaging_smoke_test.dart` already
    proves that after one send from A, Bob has exactly one incoming message and
    Charlie has exactly one incoming message, so the row-owned recipient-display
    exactly-once contract is met at the repo-owned seam
  - validation:
    reused the existing passing run of
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
    on the unchanged repo state after the GM-001 smoke-test tightening
  - blocker note:
    none; this was an acceptance-only session with no GM-004-specific code or
    test delta, and no named gate reruns were required

- `GM-005`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    widened `test/features/groups/integration/group_messaging_smoke_test.dart`
    so the quoted-reply scenario now includes Charlie and proves Alice and
    Charlie each receive Bob's quoted reply exactly once with the correct
    `quotedMessageId`, while Bob retains the local outgoing quoted reply with
    the same parent id
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`,
    `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
  - blocker note:
    none; no production-code change was required, so the direct tests were
    sufficient for this row-owned smoke-proof tightening

- `GM-007`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    added a new simultaneous-send smoke scenario in
    `test/features/groups/integration/group_messaging_smoke_test.dart` where
    Alice and Bob send via `Future.wait` and Charlie is asserted to receive
    both distinct incoming messages with two unique ids and no loss
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
  - blocker note:
    none; no production-code change was required, so the direct row-owned smoke
    proof is the acceptance evidence and no named gate rerun was needed

- `GM-008`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    widened `test/features/groups/integration/group_resume_recovery_test.dart`
    in `failed message retry after network recovery` to include Charlie and
    assert Bob and Charlie each have exactly one incoming copy of the retried
    message id after recovery while the sender's final message status resolves
    from `failed` to `sent`
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'failed message retry after network recovery'`
  - blocker note:
    none; no production-code change was required, so the targeted retry
    integration proof is the row-owned acceptance evidence

- `GM-009`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    tightened `test/features/groups/integration/group_resume_recovery_test.dart`
    in `partial delivery with inbox drain completion` so the online reader has
    the message before any offline drain, the offline readers have none before
    drain, and each offline reader receives exactly one copy after inbox drain
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'`
  - blocker note:
    none; no production-code change was required, so the targeted partial-
    delivery integration proof is the row-owned acceptance evidence

- `GM-010`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing `test/features/push/application/show_notification_use_case_test.dart`
    already proves the repo-owned backgrounded group-notification contract:
    `keeps group payload contract for local group notifications` runs with
    `AppLifecycleState.paused`, asserts exactly one notification, and verifies
    the `group:group-123` payload plus sender/body fields, while `shows
    notification when app is backgrounded` keeps the background lifecycle path
    green
  - validation:
    `flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart`
  - blocker note:
    none; the existing notification use-case tests already prove the
    backgrounded group-notification contract, so no additional code/test delta,
    named gate rerun, GM-011 deep-link work, or simulator/device-lab push
    transport scope was required

- `GM-012`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    tightened `test/features/groups/integration/group_messaging_smoke_test.dart`
    in `message is received after app restart with rejoin` so the post-restart
    proof now asserts two persisted incoming messages, unread count `2`, and
    the latest thread summary pointing to `After restart`
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
  - blocker note:
    none; no production-code change was required, so the direct restart smoke
    proof is the row-owned acceptance evidence and no named gate rerun was
    needed

- `GM-013`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing `partial delivery with inbox drain completion` scenario in
    `test/features/groups/integration/group_resume_recovery_test.dart` already
    proves one online reader receives the message before inbox drain while the
    offline readers receive the same message exactly once after inbox drain
    completes, so the mixed live plus inbox-backed delivery seam is already
    covered for this row
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'`
  - blocker note:
    none; this was an acceptance-only session with no code or test delta, and
    the tightened partial-delivery proof already covers mixed live and inbox-
    backed delivery without reopening GM-014 partial-fanout wording or
    requiring a named gate rerun

- `GM-015`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing send-failure and retry-recovery seams already prove the
    sender-disconnect contract for this row: `persists explicit inbox success
    when publish fails` in
    `test/features/groups/application/send_group_message_use_case_test.dart`
    proves publish failure persists the outgoing message as `failed` instead of
    falsely marking it `sent`, and `failed message retry after network
    recovery` in
    `test/features/groups/integration/group_resume_recovery_test.dart` proves
    later recovery completes without duplicate recipient copies
  - validation:
    `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'persists explicit inbox success when publish fails'`,
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'failed message retry after network recovery'`
  - blocker note:
    none; this was an acceptance-only session with no code or test delta, and
    the existing failure plus recovery proofs already cover the row-owned
    sender-disconnect contract, so no named gate rerun or broader
    retry/transport reopening was required

- `MR-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/add_group_member_use_case_test.dart`
    already proves admin add succeeds and non-admin callers are rejected at the
    use-case seam, while the current wired info screen only exposes the
    add-member affordance for admins
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; this was an acceptance-only session with no code or test delta, and
    the existing add-member proof already covers the row-owned authority
    contract without reopening bootstrap or duplicate-add behavior

- `MR-002`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart`
    already includes `add member syncs every member list and the new member can
    participate`, which proves the newly added member converges on the group
    state and can send a live message that existing members receive
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; a narrow smoke-test tightening was enough to make the newly added
    member's post-bootstrap participation explicit, so no production-code or
    named-gate work was required

- `MR-005`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the same `add member syncs every member list and the new member can
    participate` scenario in
    `test/features/groups/integration/group_membership_smoke_test.dart`
    proves admin, existing member, and newly added member all converge on the
    same member set and role assignments after the add
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; the same narrow smoke-test tightening supplied the missing
    member-list convergence assertions, so no production-code or broader sync
    redesign was needed

- `MR-006`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/presentation/group_info_wired_test.dart` now proves
    non-admin users do not get remove controls, while
    `test/features/groups/application/remove_group_member_use_case_test.dart`
    already proves non-admin callers are rejected and
    `test/features/groups/integration/group_membership_smoke_test.dart`
    proves the live admin-removal path updates remaining-member state
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; one narrow widget-test addition closed the missing UI-side permission
    proof, so no production-code or named-gate rerun was required before
    moving on to the confirmation and removed-state rows

- `MR-007`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `lib/features/groups/presentation/screens/group_info_wired.dart` now wraps
    member removal in an explicit confirm/cancel dialog, and
    `test/features/groups/presentation/group_info_wired_test.dart` proves the
    dialog shows consequence copy and that the downstream removal flow only
    proceeds after the confirm action
  - validation:
    `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; a narrow widget-layer product change plus matching widget-test
    tightening closed the confirmation contract without reopening remove-state
    or membership-permission scope

- `MR-009`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    includes `removed member cannot send after self-removal cleanup`, which
    proves the removed member's bridge-backed send returns `groupNotFound`,
    persists no outgoing row, and reaches no remaining member
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
  - blocker note:
    none; a narrow smoke-test addition was enough to make the post-removal send
    rejection explicit without reopening receive-blocking, notice UX, or race
    behavior

- `MR-010`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the existing `admin removes member — removed member stops receiving
    messages` scenario in
    `test/features/groups/integration/group_membership_smoke_test.dart`
    already proves the removed member keeps only pre-removal incoming traffic
    while remaining members continue to receive post-removal messages
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
  - blocker note:
    none; this was an acceptance-only session with no additional code or test
    delta, and the existing smoke proof already covered post-removal receive
    blocking exactly at the row-owned seam

- `MR-011`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/group_message_listener_test.dart` now
    includes `does not notify after self-removal deletes the group`, which
    proves self-removal deletes local group state and suppresses later
    notifications for that group
  - validation:
    `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'does not notify after self-removal deletes the group'`
  - blocker note:
    none; a narrow application-level regression was enough to close the
    post-removal notification contract without reopening mute or route UX

- `MR-012`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `lib/features/groups/presentation/screens/group_conversation_wired.dart`
    now reacts to the existing `groupRemovedStream`, and
    `test/features/groups/presentation/group_conversation_wired_test.dart`
    proves the active conversation shows `You were removed from this group.`
    and exits the route when the current group removes the local user
  - validation:
    `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'current group removal shows a notice and exits the conversation route'`
  - blocker note:
    none; a narrow conversation-route product change plus matching widget test
    closed the removed-notice contract without reopening offline removal or
    archived-group product work

- `MR-014`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `lib/features/groups/presentation/screens/group_info_wired.dart` still
    sends removal only through live `group:publish`, while
    `lib/features/groups/presentation/screens/group_conversation_wired.dart`
    only reacts after the live `groupRemovedStream` fires, so the current repo
    has no offline catch-up path that would move a removed peer into removed
    state on reconnect
  - validation:
    `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`,
    `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'current group removal shows a notice and exits the conversation route'`
  - blocker note:
    none; this session closed the row truthfully as an open repo-owned gap
    because the current removal control path is live-only and no safe offline
    reconnect proof exists in the repo today

- `MR-015`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves post-removal sends are rejected after cleanup, while
    `test/features/groups/application/send_group_message_use_case_test.dart`
    proves sends are pre-persisted before publish completes; combined with
    `Test-Flight-Improv/09-network-group-messaging.md` still recording
    best-effort ordering, the in-flight remove-versus-send boundary remains
    unproven and unspecified on the current repo state
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`,
    `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call'`
  - blocker note:
    none; this session closed the row truthfully as an open ordering gap rather
    than overclaiming the post-cleanup rejection seam as in-flight boundary
    coverage

- `MR-020`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `Test-Flight-Improv/11-group-discussion-use-case-audit.md` still records
    that groups can become leaderless if the original admin leaves, and the
    current `leave_group_use_case.dart` plus leave-flow tests still prove the
    action succeeds unconditionally instead of blocking the last admin
  - validation:
    `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`,
    `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
  - blocker note:
    none; this session closed the row truthfully as an open last-admin
    protection gap rather than overclaiming the current leave flow as safe

- `MR-022`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_edge_cases_smoke_test.dart`
    already proves a leaving member stops receiving later traffic, and
    `test/features/groups/application/leave_group_use_case_test.dart`
    proves leave removes the local group, members, and keys
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'leave group voluntarily — user stops receiving'`,
    `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`
  - blocker note:
    none; this was an acceptance-only session with no code delta, and the
    existing leave-flow proofs already covered the row-owned contract exactly

- `RJ-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves a removed member is added back to the same group and regains the
    current member/key state, while
    `test/features/groups/presentation/contact_picker_wired_test.dart` proves
    the re-invite flow sends the latest `groupKey` and `keyEpoch`, and
    `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
    proves invite bootstrap persists the fresh group, members, and key
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`,
    `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'confirming invite sends groupKey and keyEpoch from latest key'`,
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists group, members, and key for a valid invite payload'`
  - blocker note:
    none; the existing add-member plus invite-bootstrap contract was sufficient
    once the direct removed-then-rejoin smoke path was made explicit

- `RJ-002`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/add_group_member_use_case_test.dart`
    proves non-admin callers are rejected at the add-member permission seam,
    and the current repo uses that same admin-gated contract for re-invites
    after removal
  - validation:
    `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rejects when caller is not admin'`
  - blocker note:
    none; the row closed at the shared add-member permission seam without
    requiring a separate re-invite-only rejection path

- `RJ-003`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves the re-added member sends `I am back` after bootstrap and the
    current members receive it
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
  - blocker note:
    none; the row closed on the live rejoin usability proof instead of a
    narrower bootstrap-only claim

- `RJ-004`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves the re-added member receives the new `Welcome back` message after
    rejoin becomes effective
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
  - blocker note:
    none; the same smoke proof closed the post-rejoin receive contract exactly

- `RJ-006`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves the previously deleted group becomes active again with the current
    key and live send/receive restored after re-add, while
    `test/features/groups/presentation/group_list_wired_test.dart` proves the
    invite-listener path refreshes the surfaced group list when a joined group
    arrives
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`,
    `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name 'refreshes group list when groupInviteListener emits'`
  - blocker note:
    none; the current product clears removed state by recreating the group on
    re-invite rather than toggling a persistent removed banner, and that active
    contract is now explicitly covered

- `RJ-008`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    asserts the rejoined member sees the latest member list, current admin role
    assignments, and key epoch `2`, and
    `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
    keeps the invite-bootstrap persistence seam green
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`,
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists group, members, and key for a valid invite payload'`
  - blocker note:
    none; the row closed on direct current-state assertions instead of a broad
    rejoin-architecture claim

- `RJ-009`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/integration/group_membership_smoke_test.dart` now
    proves the rejoined member still sees pre-removal history and new
    post-rejoin traffic but does not see the `During removal` message sent
    while they were out of the group; the current rejoin bootstrap restores
    current state without default removed-period backfill
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
  - blocker note:
    none; the row closed with direct repo-owned evidence instead of relying on
    an undocumented history-policy assumption

- `SC-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    local Flutter tests cover app-layer admin gating for add/remove, but
    inbound membership system messages are still applied without sender-role
    authentication in `group_message_listener.dart`, so raw bypass resistance
    is not closed at the repo-owned layer; rich promotion flows are also not
    current repo-owned scope
  - validation:
    prior accepted admin-gating proofs from
    `test/features/groups/application/add_group_member_use_case_test.dart`,
    `test/features/groups/application/remove_group_member_use_case_test.dart`,
    and `test/features/groups/presentation/group_info_wired_test.dart`,
    plus code-path audit of
    `lib/features/groups/application/group_message_listener.dart`
  - blocker note:
    none; this session closed the row truthfully as an explicit repo-owned auth
    gap instead of overclaiming local UI or use-case gating as raw protocol
    proof

- `SC-003`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/member_removal_integration_test.dart`
    proves the rotated key is not distributed to the removed member and the
    remaining member adopts the new key, but intercepted-ciphertext decrypt
    failure for the removed peer still requires crypto-harness proof outside
    plain Flutter tests
  - validation:
    `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
  - blocker note:
    none; the row closed as repo-external with explicit local supporting
    evidence instead of a false ciphertext-assertion claim

- `SC-004`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/member_removal_integration_test.dart`
    and `test/features/groups/presentation/group_info_wired_test.dart` prove
    the remove flow rotates and distributes a new key to the remaining
    members, but there is still no deterministic removal-boundary test proving
    the first real post-removal send already uses the rotated epoch
  - validation:
    `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
  - blocker note:
    none; this session closed the row truthfully as partial removal-rotation
    coverage rather than overstating it as a full boundary proof

- `SC-005`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the new rejoin smoke proves the rejoined member resumes on key epoch `2`,
    but that proof still injects the fresh key through the test helper, while
    `test/features/groups/presentation/contact_picker_wired_test.dart` proves
    the re-invite path sends the latest key/epoch and
    `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
    proves bootstrap persists a supplied key/epoch
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`,
    `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'confirming invite sends groupKey and keyEpoch from latest key'`,
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists group, members, and key for a valid invite payload'`
  - blocker note:
    none; this session closed the row truthfully as partial fresh-key coverage
    rather than claiming one deterministic remove->reinvite key-issuance proof

- `SC-006`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go` prove the
    validator rejects non-member senders before delivery, while the local
    Flutter handler remains permissive if a bad payload somehow bypasses that
    validator
  - validation:
    repo inspection of `go-mknoon/node/pubsub.go` and
    `go-mknoon/node/pubsub_test.go`, plus
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'still processes messages from unknown members'`
  - blocker note:
    none; this session closed the row on repo-level validator coverage while
    keeping the permissive app-layer fallback explicit

- `SC-007`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    startup/watchdog rejoin and message catch-up are covered, but rejoin
    rebuilds from locally cached membership state and offline membership/admin
    changes are not yet replayed before a privileged operation
  - validation:
    code-path audit against `lib/features/groups/application/rejoin_group_topics_use_case.dart`,
    `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`,
    and the accepted `MR-014` residual classification
  - blocker note:
    none; this session closed the row truthfully as partial message-catch-up
    coverage, not as full stale membership/admin resync proof

- `SC-008`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
    proves same-messageId pubsub-plus-inbox deliveries deduplicate, and
    `test/features/groups/integration/group_edge_cases_smoke_test.dart`
    proves the live duplicate-delivery path stays idempotent
  - validation:
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId when pubsub and group inbox deliver same message'`,
    `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery — GroupMessageListener handles idempotently'`
  - blocker note:
    none; the row closed on exact duplicate-path delivery proof

- `SC-009`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    repo-level reject/drop tests in `go-mknoon/node/pubsub_test.go`,
    `go-mknoon/node/pubsub_decryption_failure_test.go`, and
    `integration_test/transport_e2e_test.dart` keep tampered group traffic from
    being received or persisted
  - validation:
    repo inspection of `go-mknoon/node/pubsub_test.go`,
    `go-mknoon/node/pubsub_decryption_failure_test.go`, and
    `integration_test/transport_e2e_test.dart`
  - blocker note:
    none; this session closed the row on repo-level reject/drop coverage while
    keeping notification/unread claims out of scope

- `SC-010`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
    proves replay deliveries do not create a new message row and only enrich a
    sparse existing copy when needed, but the no-duplicate-notification half is
    still an inference from listener control flow rather than a dedicated
    replay-through-notification regression
  - validation:
    `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay enriches a missing quotedMessageId'`
  - blocker note:
    none; this session closed the row truthfully as partial replay protection
    rather than a full notification-aware proof

- `SC-011`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves live post-removal receive blocking and rotated-key
    distribution cut-off, but there is still no direct queued-after-removal
    inbox-drain proof, and offline removed-state recovery remains open in
    `MR-014`
  - validation:
    `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
    plus the accepted `MR-014` residual classification
  - blocker note:
    none; this session closed the row truthfully as an explicit queue-boundary
    gap instead of overclaiming live-only removal proofs

- `SC-012`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `Test-Flight-Improv/09-network-group-messaging.md` still records ordering
    as best-effort, and `MR-015` remains an explicit remove-vs-send ordering
    gap, so in-flight membership/message boundary behavior is not currently
    closed
  - validation:
    accepted `MR-015` residual classification and source-of-truth doc audit
  - blocker note:
    none; this session closed the row truthfully as an ordering gap

- `SC-015`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `lib/features/groups/application/group_message_listener.dart` applies
    `member_added` and `member_removed` system messages without verifying
    sender admin authority, so this row still depends on future signed-event or
    validator enforcement and is not closed by current local tests
  - validation:
    code-path audit against `lib/features/groups/application/group_message_listener.dart`
    and existing member-added/member-removed listener tests
  - blocker note:
    none; the row closed truthfully as an explicit authentication gap

- `SC-017`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    message dedupe is covered for normal group traffic, but duplicate
    membership-event idempotency is not directly proven; current listener
    upsert/remove behavior reduces risk and membership events are not surfaced
    on `groupMessageStream`, yet there is still no row-owned duplicate
    membership-event regression
  - validation:
    code-path audit against `lib/features/groups/application/group_message_listener.dart`
    and existing membership-event listener tests
  - blocker note:
    none; this session closed the row truthfully as partial idempotency
    coverage rather than a full duplicate membership-event proof

- `SC-018`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    membership system messages carry no explicit sequence/version metadata, and
    `group_message_listener.dart` applies them in arrival order, so stale-event
    rollback prevention is not currently proven and may require new ordering
    metadata or validator rules
  - validation:
    code-path audit against `lib/features/groups/application/group_message_listener.dart`
  - blocker note:
    none; the row closed truthfully as an explicit stale-event rollback gap

- `GM-002`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves offline invite fallback, invite bootstrap persistence,
    inbox drain after join, and post-bootstrap participation, but it still
    lacks one exact offline-add or offline-create reconnect regression for
    this row
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'late joiner receives messages only after joining'`,
    plus repo audit of `test/features/groups/application/send_group_invite_use_case_test.dart`,
    `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`,
    and `test/features/groups/application/group_invite_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as partial offline-bootstrap coverage

- `GM-006`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    storage and UI ordering are chronological by timestamp and existing smoke
    coverage observes ordered incoming texts, but docs still record ordering
    as best-effort and there is no row-owned same-sender M1->M2 proof for
    both recipients
  - validation:
    repo audit of `Test-Flight-Improv/09-network-group-messaging.md`,
    `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`,
    and `test/features/groups/integration/group_messaging_smoke_test.dart`
  - blocker note:
    none; the row closed truthfully as partial ordering coverage

- `GM-011`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    current push-open coverage proves routing to the correct group after
    targeted catch-up, but `notification_route_target.dart` carries no message
    anchor and the repo does not prove landing on the relevant message context
  - validation:
    `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart --plain-name 'background group push opens group only after targeted group catch-up'`,
    `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart --plain-name 'terminated local notification launch prepares group target before route'`,
    and code audit of `lib/core/notifications/notification_route_target.dart`
  - blocker note:
    none; the row closed truthfully as an explicit repo-owned deep-link gap

- `GM-016`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves a temporarily disconnected member drains missed messages
    and resumes live delivery after rejoin, but there is still no explicit
    fake-network partition and heal regression with controlled split timing
    and release order
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'`,
    plus repo audit of `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
    and the accepted resume-recovery proofs
  - blocker note:
    none; the row closed truthfully as partial partition-reconnect coverage

- `MR-003`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves sends work after bootstrap and fail when the group is
    absent, but there is still no explicit bootstrap-complete gate and
    `sendGroupMessage` falls back to key epoch `0` when no key is present
  - validation:
    code-path audit of `lib/features/groups/application/send_group_message_use_case.dart`,
    plus repo audit of `test/features/groups/integration/group_membership_smoke_test.dart`
    and `test/features/groups/application/send_group_message_use_case_test.dart`
  - blocker note:
    none; the row closed truthfully as an explicit repo-owned bootstrap gap

- `MR-004`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    `ContactPickerWired` excludes existing members from the add flow and the
    add-member use case upserts duplicate peerIds to one row, but the repo
    does not prove a clear no-op or error outcome or duplicate system-event
    suppression
  - validation:
    `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'shows contacts excluding existing group members'`,
    `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'throws when member already exists — second add is upsert'`
  - blocker note:
    none; the row closed truthfully as partial duplicate-add handling

- `MR-007B`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    canceling the remove dialog is a pure no-op that leaves the member visible
    and emits no bridge or removal activity
  - validation:
    `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'canceling remove member keeps membership unchanged'`
  - blocker note:
    none; this was an acceptance-only session with exact existing UI proof

- `MR-008`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the remove-member use case appears tolerant of an already absent member
    because it snapshots the target and rebuilds config from remaining
    members, but there is still no direct non-member-remove regression and no
    asserted user-facing no-op or error contract
  - validation:
    code-path audit of `lib/features/groups/application/remove_group_member_use_case.dart`,
    plus repo audit of `test/features/groups/application/remove_group_member_use_case_test.dart`
  - blocker note:
    none; the row closed truthfully as partial absent-member handling

- `MR-013`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo broadcasts and processes `member_removed` config events so
    remaining members converge on membership state, but system messages are
    explicitly not surfaced on the UI message stream, so a visible
    `A removed C` timeline event is unproven
  - validation:
    repo audit of `lib/features/groups/presentation/screens/group_info_wired.dart`,
    `lib/features/groups/application/group_message_listener.dart`, and
    `test/features/groups/application/group_message_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as partial removal-event coverage

- `MR-021`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    current docs say roles are not richly managed after creation and admin
    transfer is missing, so there is no landed multi-admin leave contract to
    close here
  - validation:
    repo audit of `Test-Flight-Improv/11-group-discussion-use-case-audit.md`,
    `Test-Flight-Improv/09-network-group-messaging.md`, and
    `lib/features/groups/application/leave_group_use_case.dart`
  - blocker note:
    none; the row closed truthfully as unsupported by current product scope

- `MR-024`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the promotion half is out of current scope and the supported removal half
    still only broadcasts live through `group:publish`, with no repo proof
    that an offline member reconnects and syncs the updated member or admin
    list
  - validation:
    repo audit of `Test-Flight-Improv/11-group-discussion-use-case-audit.md`,
    `lib/features/groups/presentation/screens/group_info_wired.dart`, and
    `lib/features/groups/application/group_message_listener.dart`
  - blocker note:
    none; the row closed truthfully as an explicit offline-propagation gap

- `RJ-005`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves rejoin restores current state and send or receive behavior
    and separately proves incoming group messages can raise notifications, but
    there is still no exact regression showing notifications stay off while
    removed and resume only after rejoin becomes effective
  - validation:
    `flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart --plain-name 'keeps group payload contract for local group notifications'`,
    plus repo audit of `test/features/groups/integration/group_membership_smoke_test.dart`
    and `lib/features/groups/application/group_message_listener.dart`
  - blocker note:
    none; the row closed truthfully as partial notification-resume coverage

- `RJ-007`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo broadcasts and consumes re-add config events so membership state
    converges, but those events are not emitted as user-visible chat or
    timeline messages, so a visible `A added C` system event is not proven
  - validation:
    repo audit of `lib/features/groups/presentation/screens/contact_picker_wired.dart`,
    `lib/features/groups/application/group_message_listener.dart`, and
    `test/features/groups/application/group_message_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as partial re-add-event coverage

- `RJ-010`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo proves re-invites can fall back to inbox, invite bootstrap
    restores group and key state, and rejoined members regain only allowed
    post-rejoin access, but there is still no exact offline-during-re-add then
    reconnect-later end-to-end regression
  - validation:
    repo audit of `test/features/groups/application/send_group_invite_use_case_test.dart`,
    `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`,
    `test/features/groups/application/group_invite_listener_test.dart`, and
    `test/features/groups/integration/group_membership_smoke_test.dart`
  - blocker note:
    none; the row closed truthfully as partial offline re-invite coverage

- `SC-002`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    post-creation rename, photo, and description mutation are not landed
    product seams here, so the row stays explicit unsupported scope rather
    than pretending current repo work merely lacks raw protocol proof
  - validation:
    repo audit of `Test-Flight-Improv/11-group-discussion-use-case-audit.md`,
    `Test-Flight-Improv/09-network-group-messaging.md`,
    `lib/features/groups/presentation/screens/group_info_screen.dart`, and
    `lib/features/groups/presentation/screens/group_info_wired.dart`
  - blocker note:
    none; the row closed truthfully as unsupported by current product scope

- `SC-013`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the current product has a single effective admin path, not a supported
    two-admin mutation model, so concurrent admin-change convergence is
    outside current scope
  - validation:
    repo audit of `Test-Flight-Improv/11-group-discussion-use-case-audit.md`,
    `lib/features/groups/application/create_group_use_case.dart`, and
    `lib/features/groups/application/create_group_with_members_use_case.dart`
  - blocker note:
    none; the row closed truthfully as unsupported by current product scope

- `SC-014`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    sequential remove and re-add behavior exists, but the exact two-admin
    conflicting add or remove case is outside the current single-effective-
    admin product contract
  - validation:
    repo audit of `Test-Flight-Improv/11-group-discussion-use-case-audit.md`,
    `lib/features/groups/application/create_group_with_members_use_case.dart`,
    and `test/features/groups/integration/group_membership_smoke_test.dart`
  - blocker note:
    none; the row closed truthfully as unsupported by current product scope

- `SC-016`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    group send status is explicitly defined and tested as `sent` or inbox-
    backed success on partial fan-out and zero-peer fallback, so this row
    closes at the current product-rule seam
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'`,
    plus repo audit of `lib/features/groups/application/send_group_message_use_case.dart`
    and `test/features/groups/application/send_group_message_use_case_test.dart`
  - blocker note:
    none; the row closed on current send-status contract evidence

- `UX-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    current behavior implies future-from-membership plus post-join inbox
    replay, but the repo still lacks one direct row-owned policy test that
    pins new-member history semantics explicitly
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'late joiner receives messages only after joining'`,
    plus repo audit of `test/features/groups/application/group_invite_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as partial history-policy coverage

- `UX-005`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    unread counting and message deduplication are both covered, but the repo
    still lacks one row-owned regression proving unread counters stay correct
    across duplicate, retry, and reconnect flows end to end
  - validation:
    `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name 'shows unread counts'`,
    plus repo audit of `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
    and `test/features/groups/integration/group_resume_recovery_test.dart`
  - blocker note:
    none; the row closed truthfully as partial unread-count coverage

- `UX-006`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    bidi sanitization and mixed RTL or LTR preview rendering are covered, but
    the repo still lacks one direct end-to-end row proof for long text, emoji,
    and special-character behavior together
  - validation:
    repo audit of `test/features/groups/application/send_group_message_use_case_test.dart`,
    `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`,
    `test/features/groups/presentation/group_card_bidi_test.dart`, and
    `test/features/groups/presentation/group_list_screen_bidi_test.dart`
  - blocker note:
    none; the row closed truthfully as partial text-format coverage

- `UX-007`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    attachments and durable failed-media recovery are real and tested, but the
    repo does not prove a large-payload or explicit size-limit contract for
    this row
  - validation:
    `flutter test --no-pub test/features/groups/integration/announcement_happy_path_test.dart --plain-name 'announcement happy path: create, admin send, reader read-only receive, member react'`,
    plus repo audit of `test/features/groups/application/send_group_message_use_case_test.dart`
    and `test/features/groups/integration/group_resume_recovery_test.dart`
  - blocker note:
    none; the row closed truthfully as partial attachment-boundary coverage

- `UX-008`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    store-and-forward replay exists, but the current repo does not define or
    prove a retention or TTL expiry boundary for group messages
  - validation:
    repo audit of `Test-Flight-Improv/09-network-group-messaging.md` and
    `test/features/groups/application/group_invite_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as contract-undefined retention behavior

- `UX-009`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the repo documents scale targets and profiling ranges, not a hard
    max-group-size enforcement rule
  - validation:
    repo audit of `Test-Flight-Improv/09-network-group-messaging.md`
  - blocker note:
    none; the row closed truthfully as contract-undefined max-size behavior

- `UX-010`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    member-list convergence after add, remove, and restart exists, but the
    exact reconnect-after-membership-churn comparison across all peers is
    still only partially covered
  - validation:
    `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'late joiner receives messages only after joining'`,
    plus repo audit of `test/features/groups/integration/group_membership_smoke_test.dart`
    and `test/features/groups/application/group_message_listener_test.dart`
  - blocker note:
    none; the row closed truthfully as partial reconnect-convergence coverage

- `UX-013`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    current repo proof is multi-peer convergence only, with no same-user
    multi-device contract or regression to close this row honestly
  - validation:
    repo audit of `Test-Flight-Improv/09-network-group-messaging.md` and
    `test/features/groups/integration/group_membership_smoke_test.dart`
  - blocker note:
    none; the row closed truthfully as contract-undefined multi-device scope

- `UX-015`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    announcement and admin-only send is a landed feature with direct auth, UI,
    and end-to-end proof in the current repo
  - validation:
    `flutter test --no-pub test/features/groups/integration/announcement_happy_path_test.dart --plain-name 'announcement happy path: create, admin send, reader read-only receive, member react'`,
    plus repo audit of `test/features/groups/application/send_group_message_use_case_test.dart`
    and `test/features/groups/presentation/group_conversation_wired_test.dart`
  - blocker note:
    none; this was an acceptance-only session with existing announcement proof

- `CLOSURE-001`
  - closure verdict: `accepted`
  - execution verdict: `accepted`
  - closure docs touched:
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - evidence:
    the matrix and breakdown now tell the same truthful row-by-row story for
    covered seams, partial seams, explicit repo-owned gaps, unsupported
    features, and policy-undefined optional rows
  - validation:
    consistency audit of the matrix and breakdown plus focused reruns of
    `group_info_wired_test.dart`, `add_group_member_use_case_test.dart`,
    `contact_picker_wired_test.dart`, `group_resume_recovery_test.dart`,
    `app_root_notification_open_test.dart`,
    `show_notification_use_case_test.dart`,
    `announcement_happy_path_test.dart`,
    `group_messaging_smoke_test.dart`,
    `chat_and_group_push_open_flow_test.dart`, and
    `group_list_wired_test.dart`; no final gate rerun was required because
    this closing pass changed docs only
  - blocker note:
    none; the final program verdict is persisted below

## Current pipeline state

- sessions processed so far: `85/85`
- sessions accepted so far: `74`
- sessions resolved as `stale/already-covered`: `11`
- latest accepted session: `CLOSURE-001`
- next runnable session in order: `none`
- current doc state: `accepted_with_explicit_follow_up`
- final program verdict is persisted below

## Final program acceptance

- final program verdict:
  `accepted_with_explicit_follow_up`
- docs updated:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`,
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- what is now closed:
  every source row now resolves to one explicit current-state classification,
  and the matrix plus breakdown agree on covered seams, partial seams,
  repo-owned gaps, unsupported product scope, and contract-undefined optional
  rows
- still-open blocker for safe continuation:
  none
- explicit follow-up that remains:
  rows classified as `partial`, `open`, `unsupported`, or
  `contract-undefined` remain visible as truthful follow-up work instead of
  being silently overstated as covered
- safe-to-close rationale:
  all `85/85` sessions are resolved, the accepted plus
  `stale/already-covered` counts reconcile to the full breakdown, and this
  artifact now carries the persisted final verdict required by the rollout
  contract

## Ordered session breakdown

### Session GM-001

- Title:
  `Source row GM-001: Create group successfully`
- Session id:
  `GM-001`
- Source row id:
  `GM-001`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-001-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-001 (Create group successfully), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-003

- Title:
  `Source row GM-003: Online fan-out`
- Session id:
  `GM-003`
- Source row id:
  `GM-003`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-003-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-003 (Online fan-out), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-004

- Title:
  `Source row GM-004: Exactly-once display`
- Session id:
  `GM-004`
- Source row id:
  `GM-004`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-004-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-004 (Exactly-once display), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-005

- Title:
  `Source row GM-005: Reply fan-out`
- Session id:
  `GM-005`
- Source row id:
  `GM-005`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-005-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-005 (Reply fan-out), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-007

- Title:
  `Source row GM-007: Simultaneous send`
- Session id:
  `GM-007`
- Source row id:
  `GM-007`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-007-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-007 (Simultaneous send), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-008

- Title:
  `Source row GM-008: Retry without duplicates`
- Session id:
  `GM-008`
- Source row id:
  `GM-008`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-008-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-008 (Retry without duplicates), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-009

- Title:
  `Source row GM-009: Offline recipient receives later`
- Session id:
  `GM-009`
- Source row id:
  `GM-009`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-009-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-009 (Offline recipient receives later), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-010

- Title:
  `Source row GM-010: Background notification`
- Session id:
  `GM-010`
- Source row id:
  `GM-010`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-010-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-010 (Background notification), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-012

- Title:
  `Source row GM-012: App restart recovery`
- Session id:
  `GM-012`
- Source row id:
  `GM-012`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-012-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-012 (App restart recovery), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-013

- Title:
  `Source row GM-013: Mixed delivery paths`
- Session id:
  `GM-013`
- Source row id:
  `GM-013`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-013-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-013 (Mixed delivery paths), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-014

- Title:
  `Source row GM-014: Partial fan-out`
- Session id:
  `GM-014`
- Source row id:
  `GM-014`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-014-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-014 (Partial fan-out), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-015

- Title:
  `Source row GM-015: Sender disconnected behavior`
- Session id:
  `GM-015`
- Source row id:
  `GM-015`
- Priority:
  `P0`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-015-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-015 (Sender disconnected behavior), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-001

- Title:
  `Source row MR-001: Only admin can add members`
- Session id:
  `MR-001`
- Source row id:
  `MR-001`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-001-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-001 (Only admin can add members), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-002

- Title:
  `Source row MR-002: Add member success`
- Session id:
  `MR-002`
- Source row id:
  `MR-002`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-002-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-002 (Add member success), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-005

- Title:
  `Source row MR-005: Member list sync after add`
- Session id:
  `MR-005`
- Source row id:
  `MR-005`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-005-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-005 (Member list sync after add), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-006

- Title:
  `Source row MR-006: Only admin can remove members`
- Session id:
  `MR-006`
- Source row id:
  `MR-006`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-006-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-006 (Only admin can remove members), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-007

- Title:
  `Source row MR-007: Remove member confirmation`
- Session id:
  `MR-007`
- Source row id:
  `MR-007`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-007-plan.md`
- Exact scope:
  - close source row MR-007 (Remove member confirmation) with the smallest repo-owned product and regression change set needed for the current contract, then update the matrix truth for that row
- Ownership:
  - `code changes + tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current repo facts suggest the user-visible contract is missing or under-surfaced, so plan a narrow product plus regression slice rather than evidence only.

### Session MR-009

- Title:
  `Source row MR-009: Removed member loses send permission`
- Session id:
  `MR-009`
- Source row id:
  `MR-009`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-009-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-009 (Removed member loses send permission), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-010

- Title:
  `Source row MR-010: Removed member loses receive permission`
- Session id:
  `MR-010`
- Source row id:
  `MR-010`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-010-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-010 (Removed member loses receive permission), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-011

- Title:
  `Source row MR-011: Removed member loses notifications`
- Session id:
  `MR-011`
- Source row id:
  `MR-011`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-011-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-011 (Removed member loses notifications), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-012

- Title:
  `Source row MR-012: Removed member is notified`
- Session id:
  `MR-012`
- Source row id:
  `MR-012`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-012-plan.md`
- Exact scope:
  - close source row MR-012 (Removed member is notified) with the smallest repo-owned product and regression change set needed for the current contract, then update the matrix truth for that row
- Ownership:
  - `code changes + tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current repo facts suggest the user-visible contract is missing or under-surfaced, so plan a narrow product plus regression slice rather than evidence only.

### Session MR-014

- Title:
  `Source row MR-014: Removed while offline`
- Session id:
  `MR-014`
- Source row id:
  `MR-014`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-014-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-014 (Removed while offline), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-015

- Title:
  `Source row MR-015: Removed while typing/sending`
- Session id:
  `MR-015`
- Source row id:
  `MR-015`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-015-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-015 (Removed while typing/sending), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-016

- Title:
  `Source row MR-016: Admin can promote another admin`
- Session id:
  `MR-016`
- Source row id:
  `MR-016`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-016-plan.md`
- Exact scope:
  - confirm that source row MR-016 (Admin can promote another admin) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Promotion/demotion rows stay out of scope because roles are not richly managed after creation in current docs.

### Session MR-017

- Title:
  `Source row MR-017: Non-admin cannot self-promote`
- Session id:
  `MR-017`
- Source row id:
  `MR-017`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-017-plan.md`
- Exact scope:
  - confirm that source row MR-017 (Non-admin cannot self-promote) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Promotion/demotion rows stay out of scope because roles are not richly managed after creation in current docs.

### Session MR-020

- Title:
  `Source row MR-020: At least one admin remains`
- Session id:
  `MR-020`
- Source row id:
  `MR-020`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-020-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-020 (At least one admin remains), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-022

- Title:
  `Source row MR-022: Member can leave group`
- Session id:
  `MR-022`
- Source row id:
  `MR-022`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-022-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-022 (Member can leave group), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-001

- Title:
  `Source row RJ-001: Admin can re-invite removed member`
- Session id:
  `RJ-001`
- Source row id:
  `RJ-001`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-001-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-001 (Admin can re-invite removed member), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-002

- Title:
  `Source row RJ-002: Non-admin cannot re-invite`
- Session id:
  `RJ-002`
- Source row id:
  `RJ-002`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-002-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-002 (Non-admin cannot re-invite), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-003

- Title:
  `Source row RJ-003: Re-invited member can send again`
- Session id:
  `RJ-003`
- Source row id:
  `RJ-003`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-003-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-003 (Re-invited member can send again), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-004

- Title:
  `Source row RJ-004: Re-invited member can receive again`
- Session id:
  `RJ-004`
- Source row id:
  `RJ-004`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-004-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-004 (Re-invited member can receive again), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-006

- Title:
  `Source row RJ-006: Rejoin clears removed state`
- Session id:
  `RJ-006`
- Source row id:
  `RJ-006`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-006-plan.md`
- Exact scope:
  - close source row RJ-006 (Rejoin clears removed state) with the smallest repo-owned product and regression change set needed for the current contract, then update the matrix truth for that row
- Ownership:
  - `code changes + tests`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current repo facts suggest the user-visible contract is missing or under-surfaced, so plan a narrow product plus regression slice rather than evidence only.

### Session RJ-008

- Title:
  `Source row RJ-008: Rejoined member sees current membership and admins`
- Session id:
  `RJ-008`
- Source row id:
  `RJ-008`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-008-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-008 (Rejoined member sees current membership and admins), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-009

- Title:
  `Source row RJ-009: Removed-period history is not exposed by default`
- Session id:
  `RJ-009`
- Source row id:
  `RJ-009`
- Priority:
  `P0`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-009-plan.md`
- Exact scope:
  - audit source row RJ-009 (Removed-period history is not exposed by default) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-001

- Title:
  `Source row SC-001: UI restrictions are not the only restrictions`
- Session id:
  `SC-001`
- Source row id:
  `SC-001`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-001-plan.md`
- Exact scope:
  - map source row SC-001 (UI restrictions are not the only restrictions) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-003

- Title:
  `Source row SC-003: Removed member cannot decrypt future messages`
- Session id:
  `SC-003`
- Source row id:
  `SC-003`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-003-plan.md`
- Exact scope:
  - map source row SC-003 (Removed member cannot decrypt future messages) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-004

- Title:
  `Source row SC-004: Group key/epoch rotates on removal`
- Session id:
  `SC-004`
- Source row id:
  `SC-004`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-004-plan.md`
- Exact scope:
  - audit source row SC-004 (Group key/epoch rotates on removal) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-005

- Title:
  `Source row SC-005: Group key/epoch updates correctly on re-invite`
- Session id:
  `SC-005`
- Source row id:
  `SC-005`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-005-plan.md`
- Exact scope:
  - audit source row SC-005 (Group key/epoch updates correctly on re-invite) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-006

- Title:
  `Source row SC-006: Unknown/non-member sender is rejected`
- Session id:
  `SC-006`
- Source row id:
  `SC-006`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-006-plan.md`
- Exact scope:
  - map source row SC-006 (Unknown/non-member sender is rejected) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-007

- Title:
  `Source row SC-007: Stale client resync`
- Session id:
  `SC-007`
- Source row id:
  `SC-007`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-007-plan.md`
- Exact scope:
  - audit source row SC-007 (Stale client resync) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-008

- Title:
  `Source row SC-008: Duplicate-path dedupe`
- Session id:
  `SC-008`
- Source row id:
  `SC-008`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-008-plan.md`
- Exact scope:
  - audit source row SC-008 (Duplicate-path dedupe) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-009

- Title:
  `Source row SC-009: Tampered message rejection`
- Session id:
  `SC-009`
- Source row id:
  `SC-009`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-009-plan.md`
- Exact scope:
  - map source row SC-009 (Tampered message rejection) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-010

- Title:
  `Source row SC-010: Replay protection`
- Session id:
  `SC-010`
- Source row id:
  `SC-010`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-010-plan.md`
- Exact scope:
  - audit source row SC-010 (Replay protection) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-011

- Title:
  `Source row SC-011: Post-removal store-and-forward cut-off`
- Session id:
  `SC-011`
- Source row id:
  `SC-011`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-011-plan.md`
- Exact scope:
  - audit source row SC-011 (Post-removal store-and-forward cut-off) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-012

- Title:
  `Source row SC-012: Membership change ordering vs in-flight messages`
- Session id:
  `SC-012`
- Source row id:
  `SC-012`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-012-plan.md`
- Exact scope:
  - audit source row SC-012 (Membership change ordering vs in-flight messages) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-015

- Title:
  `Source row SC-015: Membership and role events are authenticated`
- Session id:
  `SC-015`
- Source row id:
  `SC-015`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-015-plan.md`
- Exact scope:
  - map source row SC-015 (Membership and role events are authenticated) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-017

- Title:
  `Source row SC-017: Duplicate membership or role event is idempotent`
- Session id:
  `SC-017`
- Source row id:
  `SC-017`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-017-plan.md`
- Exact scope:
  - audit source row SC-017 (Duplicate membership or role event is idempotent) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-018

- Title:
  `Source row SC-018: Older membership or role event cannot roll back newer state`
- Session id:
  `SC-018`
- Source row id:
  `SC-018`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-018-plan.md`
- Exact scope:
  - audit source row SC-018 (Older membership or role event cannot roll back newer state) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session GM-002

- Title:
  `Source row GM-002: Create/add with offline member bootstrap`
- Session id:
  `GM-002`
- Source row id:
  `GM-002`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-002-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-002 (Create/add with offline member bootstrap), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-006

- Title:
  `Source row GM-006: Sequential same-sender ordering`
- Session id:
  `GM-006`
- Source row id:
  `GM-006`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-006-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-006 (Sequential same-sender ordering), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-011

- Title:
  `Source row GM-011: Notification deep link`
- Session id:
  `GM-011`
- Source row id:
  `GM-011`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-011-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-011 (Notification deep link), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session GM-016

- Title:
  `Source row GM-016: Network partition and reconnect`
- Session id:
  `GM-016`
- Source row id:
  `GM-016`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-GM-016-plan.md`
- Exact scope:
  - audit existing coverage for source row GM-016 (Network partition and reconnect), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` or `transport` only when startup, reconnect, resume, or media wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-003

- Title:
  `Source row MR-003: New member cannot send before bootstrap completes`
- Session id:
  `MR-003`
- Source row id:
  `MR-003`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-003-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-003 (New member cannot send before bootstrap completes), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-004

- Title:
  `Source row MR-004: Add existing member handled cleanly`
- Session id:
  `MR-004`
- Source row id:
  `MR-004`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-004-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-004 (Add existing member handled cleanly), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-007B

- Title:
  `Source row MR-007B: Remove member cancellation keeps membership unchanged`
- Session id:
  `MR-007B`
- Source row id:
  `MR-007B`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-007B-plan.md`
- Exact scope:
  - close source row MR-007B (Remove member cancellation keeps membership unchanged) with the smallest repo-owned product and regression change set needed for the current contract, then update the matrix truth for that row
- Ownership:
  - `code changes + tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current repo facts suggest the user-visible contract is missing or under-surfaced, so plan a narrow product plus regression slice rather than evidence only.

### Session MR-008

- Title:
  `Source row MR-008: Remove non-member handled cleanly`
- Session id:
  `MR-008`
- Source row id:
  `MR-008`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-008-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-008 (Remove non-member handled cleanly), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-013

- Title:
  `Source row MR-013: Remaining members see removal system event`
- Session id:
  `MR-013`
- Source row id:
  `MR-013`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-013-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-013 (Remaining members see removal system event), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-018

- Title:
  `Source row MR-018: Promote non-member handled cleanly`
- Session id:
  `MR-018`
- Source row id:
  `MR-018`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-018-plan.md`
- Exact scope:
  - confirm that source row MR-018 (Promote non-member handled cleanly) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Promotion/demotion rows stay out of scope because roles are not richly managed after creation in current docs.

### Session MR-019

- Title:
  `Source row MR-019: System event for admin promotion`
- Session id:
  `MR-019`
- Source row id:
  `MR-019`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-019-plan.md`
- Exact scope:
  - confirm that source row MR-019 (System event for admin promotion) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Promotion/demotion rows stay out of scope because roles are not richly managed after creation in current docs.

### Session MR-021

- Title:
  `Source row MR-021: Admin leave flow with multiple admins`
- Session id:
  `MR-021`
- Source row id:
  `MR-021`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-021-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-021 (Admin leave flow with multiple admins), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session MR-023

- Title:
  `Source row MR-023: Non-admin cannot edit group metadata`
- Session id:
  `MR-023`
- Source row id:
  `MR-023`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-023-plan.md`
- Exact scope:
  - confirm that source row MR-023 (Non-admin cannot edit group metadata) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Metadata editing rows stay out of scope because current docs say name/avatar/description management is not surfaced after creation.

### Session MR-024

- Title:
  `Source row MR-024: Admin change propagates to offline members`
- Session id:
  `MR-024`
- Source row id:
  `MR-024`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-MR-024-plan.md`
- Exact scope:
  - audit existing coverage for source row MR-024 (Admin change propagates to offline members), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-005

- Title:
  `Source row RJ-005: Notifications resume after rejoin`
- Session id:
  `RJ-005`
- Source row id:
  `RJ-005`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-005-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-005 (Notifications resume after rejoin), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-007

- Title:
  `Source row RJ-007: System event for re-add`
- Session id:
  `RJ-007`
- Source row id:
  `RJ-007`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-007-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-007 (System event for re-add), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session RJ-010

- Title:
  `Source row RJ-010: Re-invite while removed member is offline`
- Session id:
  `RJ-010`
- Source row id:
  `RJ-010`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-RJ-010-plan.md`
- Exact scope:
  - audit existing coverage for source row RJ-010 (Re-invite while removed member is offline), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`; add `baseline` when UI or notification routing changes and `transport` when offline or rejoin wiring changes`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session SC-002

- Title:
  `Source row SC-002: Unauthorized metadata changes rejected at protocol layer`
- Session id:
  `SC-002`
- Source row id:
  `SC-002`
- Priority:
  `P1`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `repo_external_proof`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-002-plan.md`
- Exact scope:
  - map source row SC-002 (Unauthorized metadata changes rejected at protocol layer) to the current repo-owned proof surface, record what remains Go-side, protocol-injection, ciphertext-capture, or device-lab proof, and avoid pretending plain Flutter tests fully close the row
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Keep the row in the breakdown, but do not overclaim pure Flutter proof where the matrix itself asks for raw protocol, ciphertext, or injected-event evidence.

### Session SC-013

- Title:
  `Source row SC-013: Concurrent admin changes converge safely`
- Session id:
  `SC-013`
- Source row id:
  `SC-013`
- Priority:
  `P1`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-013-plan.md`
- Exact scope:
  - audit source row SC-013 (Concurrent admin changes converge safely) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-014

- Title:
  `Source row SC-014: Conflicting add/remove of same member converges deterministically`
- Session id:
  `SC-014`
- Source row id:
  `SC-014`
- Priority:
  `P1`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-014-plan.md`
- Exact scope:
  - audit source row SC-014 (Conflicting add/remove of same member converges deterministically) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session SC-016

- Title:
  `Source row SC-016: Local send status reflects partial success accurately`
- Session id:
  `SC-016`
- Source row id:
  `SC-016`
- Priority:
  `P1`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-SC-016-plan.md`
- Exact scope:
  - audit source row SC-016 (Local send status reflects partial success accurately) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` when Flutter production code changes; use direct fake-network or bridge suites for proof-heavy rows`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-001

- Title:
  `Source row UX-001: New member history policy`
- Session id:
  `UX-001`
- Source row id:
  `UX-001`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-001-plan.md`
- Exact scope:
  - audit source row UX-001 (New member history policy) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-002

- Title:
  `Source row UX-002: Group rename`
- Session id:
  `UX-002`
- Source row id:
  `UX-002`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-002-plan.md`
- Exact scope:
  - confirm that source row UX-002 (Group rename) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Metadata editing rows stay out of scope because current docs say name/avatar/description management is not surfaced after creation.

### Session UX-004

- Title:
  `Source row UX-004: Mute notifications per group`
- Session id:
  `UX-004`
- Source row id:
  `UX-004`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-004-plan.md`
- Exact scope:
  - confirm that source row UX-004 (Mute notifications per group) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Per-group mute stays out of scope because the current repo has no app-layer mute flow.

### Session UX-005

- Title:
  `Source row UX-005: Unread count correctness`
- Session id:
  `UX-005`
- Source row id:
  `UX-005`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-005-plan.md`
- Exact scope:
  - audit existing coverage for source row UX-005 (Unread count correctness), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session UX-006

- Title:
  `Source row UX-006: Long text / emoji / RTL / special characters`
- Session id:
  `UX-006`
- Source row id:
  `UX-006`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-006-plan.md`
- Exact scope:
  - audit existing coverage for source row UX-006 (Long text / emoji / RTL / special characters), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session UX-010

- Title:
  `Source row UX-010: Member list consistency after reconnect`
- Session id:
  `UX-010`
- Source row id:
  `UX-010`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-010-plan.md`
- Exact scope:
  - audit existing coverage for source row UX-010 (Member list consistency after reconnect), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session UX-003

- Title:
  `Source row UX-003: Group picture/description update`
- Session id:
  `UX-003`
- Source row id:
  `UX-003`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-003-plan.md`
- Exact scope:
  - confirm that source row UX-003 (Group picture/description update) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Metadata editing rows stay out of scope because current docs say name/avatar/description management is not surfaced after creation.

### Session UX-007

- Title:
  `Source row UX-007: Large message or attachment`
- Session id:
  `UX-007`
- Source row id:
  `UX-007`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-007-plan.md`
- Exact scope:
  - audit source row UX-007 (Large message or attachment) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-008

- Title:
  `Source row UX-008: Store-and-forward expiry / retention boundary`
- Session id:
  `UX-008`
- Source row id:
  `UX-008`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-008-plan.md`
- Exact scope:
  - audit source row UX-008 (Store-and-forward expiry / retention boundary) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-009

- Title:
  `Source row UX-009: Max group size limit`
- Session id:
  `UX-009`
- Source row id:
  `UX-009`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-009-plan.md`
- Exact scope:
  - audit source row UX-009 (Max group size limit) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-011

- Title:
  `Source row UX-011: Admin demotion / revoke admin`
- Session id:
  `UX-011`
- Source row id:
  `UX-011`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-011-plan.md`
- Exact scope:
  - confirm that source row UX-011 (Admin demotion / revoke admin) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Promotion/demotion rows stay out of scope because roles are not richly managed after creation in current docs.

### Session UX-012

- Title:
  `Source row UX-012: Invite accept / decline / expiry`
- Session id:
  `UX-012`
- Source row id:
  `UX-012`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-012-plan.md`
- Exact scope:
  - confirm that source row UX-012 (Invite accept / decline / expiry) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Explicit invite accept/decline stays out of scope because current group invites do not have strong expiry/acceptance semantics.

### Session UX-013

- Title:
  `Source row UX-013: Multi-device state convergence`
- Session id:
  `UX-013`
- Source row id:
  `UX-013`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_repo_evidence`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-013-plan.md`
- Exact scope:
  - audit source row UX-013 (Multi-device state convergence) against current code, tests, and closure docs, then classify it as already covered, repo-owned gap, or residual evidence-only work before opening broader implementation
- Ownership:
  - `evidence only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - Current family-level coverage exists, but the exact row still needs explicit row-owned evidence or classification before it can be called closed.

### Session UX-014

- Title:
  `Source row UX-014: Group dissolve / deletion`
- Session id:
  `UX-014`
- Source row id:
  `UX-014`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `unsupported_product_scope`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-014-plan.md`
- Exact scope:
  - confirm that source row UX-014 (Group dissolve / deletion) is out of scope for the current landed product contract, cite the repo docs proving that status, and keep the row from silently creating feature-build work
- Ownership:
  - `no execution because the row is unsupported in the current product contract`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Likely named gates:
  - `none; doc-only out-of-scope classification`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md` only if maintenance guidance is stale
- Notes:
  - Dissolution stays out of scope because the repo docs record no explicit admin-initiated dissolve workflow.

### Session UX-015

- Title:
  `Source row UX-015: Admin-only send / announcement mode`
- Session id:
  `UX-015`
- Source row id:
  `UX-015`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-UX-015-plan.md`
- Exact scope:
  - audit existing coverage for source row UX-015 (Admin-only send / announcement mode), tighten or add the narrowest direct regression proving the row, and reclassify the row as covered only after exact test evidence exists
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups` when group production code changes; otherwise rely on direct push or group suites`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- Notes:
  - The current tree already appears to own the product seam; the likely remaining work is row-specific proof, not a new architecture slice.

### Session CLOSURE-001

- Title:
  `Final matrix closure refresh and gate classification`
- Session id:
  `CLOSURE-001`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-CLOSURE-001-plan.md`
- Exact scope:
  - refresh the source matrix and this breakdown with final per-row truth after the row-owned sessions finish
  - update gate definitions only when the landed rollout actually changes a frozen gate or direct-suite classification
  - emit the final doc verdict as `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` based on row-owned outcomes
- Ownership:
  - `closure docs only`
- Likely code-entry files:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely direct tests/regressions:
  - rerun the accepted proof batches for the row-owned sessions that changed code or tests
  - rerun `./scripts/run_test_gates.sh groups` when group production code changed
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when Flutter production code changed
  - `./scripts/run_test_gates.sh completeness-check` only if `test-gate-definitions.md` changed
- Dependency on earlier sessions:
  - all row-owned sessions that remain runnable
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`, and any touched stable closure docs
- Notes:
  - this is the only non-row session in the artifact

## Why this is not fewer sessions

- The user explicitly asked for row-by-row ownership, so broad seam buckets would lose traceability and recreate the earlier problem.
- The matrix mixes supported flows, unsupported optional features, repo-external proof rows, and likely test-only gaps; collapsing them would blur closure truth and scope ownership.
- Keeping source row ids as session ids lets later planning, execution, and closure report truth per row instead of per subsystem.
- `CLOSURE-001` is the only non-row session because final matrix truth and gate classification necessarily span the whole rollout.
