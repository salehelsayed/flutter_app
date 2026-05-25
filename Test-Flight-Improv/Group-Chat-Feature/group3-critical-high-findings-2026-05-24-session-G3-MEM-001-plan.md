# G3-MEM-001 Session Plan And Closure

Source rows: G3-001, G3-004, G3-005, G3-006, G3-007, G3-009, G3-010.

## Scope

- Reject `addGroupMember` group mismatches before persistence or config sync.
- Prevent invite-only actors from assigning admin role or permission overrides.
- Require manageRoles/admin authority when removing an admin.
- Reject stale/equal membership event times for add/remove and prefer explicit config `joinedAt`.
- Serialize same-group membership mutations with an application-level async lock.
- Preserve removed-member snapshots before deletion.
- Reject add/remove mutations on dissolved groups.

## Closure Evidence

- Implemented in membership mutation use cases and membership watermark helper.
- Focused tests added in add/remove use case tests and `group_member_test.dart`.
- Verification: included in the controller focused gate, `+169: All tests passed!`.

## Verdict

Accepted and closed.
