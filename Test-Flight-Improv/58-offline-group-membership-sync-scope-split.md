# Offline Group Membership Sync Scope Split

## 1. Title and Type

- Title: Split offline bystander membership sync from unsupported admin-change propagation
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`

## 2. Problem Statement

- A disconnected member should be able to reconnect and see the latest supported membership state for the group.
- The current `MR-024` row mixes two different expectations in one contract:
  - supported offline catch-up for membership-list changes
  - unsupported admin-change propagation such as promotion flows that are not part of the current product scope
- From a user perspective, that mixed row makes it unclear what outcome the repo is actually expected to deliver after reconnect.

## 3. Impact Analysis

- Affects members who reconnect after membership changes happened while they were offline.
- Appears in reconnect and inbox-drain scenarios after add/remove/member-list changes.
- Severity is medium to high because the mixed contract blocks honest rollout closure even though some offline membership-sync behavior is already supported.
- The current in-scope gap matrix keeps `MR-024` open because the row combines repo-owned and out-of-scope expectations in one line.

## 4. Current State

- `MR-014` is now closed in `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, which proves offline catch-up for the removed peer's own removal state.
- `MR-024` in the same matrix still says the row lacks repo proof that an offline bystander reconnects with the latest member/admin list, while the promotion/admin-change half remains out of current scope.
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md` still lists richer admin tooling such as admin transfer as missing product scope.
- The current likely code and test surfaces for repo-owned offline membership convergence are:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- The current blocker is not just missing proof. It is also that one source row asks for both supported offline bystander convergence and unsupported admin-change propagation at the same time.

## 5. Scope Clarification

- In scope:
  - define the repo-owned reconnect expectation for an offline bystander after supported membership changes such as add/remove
  - make that reconnect expectation independently testable
  - keep unsupported admin-change propagation out of the repo-owned closure bar until the product supports it
- Not in scope:
  - adding new admin promotion, demotion, or transfer features
  - retroactively treating unsupported role-management flows as current product requirements
  - unrelated notification or message-ordering behavior
- Accepted ambiguity for the later implementation pass:
  - this spec does not choose whether the final result should be one split matrix row, two matrix rows, or one repo-owned row plus one explicit out-of-scope row; it only requires that supported offline bystander sync be separated from unsupported admin-change propagation

## 6. Test Cases

### Happy Path

- If one member is offline while another member is added or removed, the offline bystander reconnects and sees the same final member list as the peers who stayed online.
- After reconnect, the offline bystander can interact with the group according to the converged supported membership state.

### Edge Cases

- If multiple supported membership changes happen while the bystander is offline, reconnect still converges to the same final member list seen by live peers.
- If the offline bystander reconnects after inbox replay and topic rejoin complete, the surfaced member list and role badges match the supported current state rather than a stale cached view.
- Unsupported admin-promotion or admin-transfer expectations are not silently treated as repo-owned failures in the same reconnect contract.

### Regressions To Preserve

- Existing removed-peer offline catch-up behavior already closed by `MR-014` must keep working.
- Existing repo-owned add/remove membership convergence must keep working for online peers while the offline-bystander reconnect contract is clarified and tested.

