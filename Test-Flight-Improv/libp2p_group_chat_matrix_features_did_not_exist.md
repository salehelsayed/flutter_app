# Libp2p Group Chat: Features That Did Not Exist

This table contains the matrix rows marked `Unsupported`. These journeys were written in the matrix, but the corresponding product capability is not currently landed in this repo.

Source: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

Count: 15

| Test ID | Section | Scenario | Status | Why |
|---|---|---|---|---|
| MR-016 | Membership and Role Control | Admin can promote another admin | Unsupported | current repo docs say roles are not richly managed after creation, so admin-promotion flows are out of the landed product contract rather than missing test coverage. |
| MR-017 | Membership and Role Control | Non-admin cannot self-promote | Unsupported | current repo docs say roles are not richly managed after creation, so self-promotion checks are outside the landed product contract. |
| MR-018 | Membership and Role Control | Promote non-member handled cleanly | Unsupported | current repo docs keep promotion and richer role-management flows out of scope after creation, so this non-member promotion row should stay explicit product-scope debt rather than reopen feature work silently. |
| MR-019 | Membership and Role Control | System event for admin promotion | Unsupported | admin promotion is not a landed role-management feature in the current product, so the related system-event row remains out of scope. |
| MR-021 | Membership and Role Control | Admin leave flow with multiple admins | Unsupported | current docs say roles are not richly managed after creation and admin transfer is missing, so there is no landed multi-admin leave contract to close here. |
| MR-023 | Membership and Role Control | Non-admin cannot edit group metadata | Unsupported | post-creation metadata editing is not surfaced in the landed product, so this row stays explicit out-of-scope behavior instead of silently creating new feature work. |
| SC-002 | Security, Correctness, and Convergence | Unauthorized metadata changes rejected at protocol layer | Unsupported | post-creation rename, photo, and description mutation are not landed product seams here, so this row should stay explicit unsupported scope rather than pretending current repo work merely lacks raw protocol proof. |
| SC-013 | Security, Correctness, and Convergence | Concurrent admin changes converge safely | Unsupported | the current product has a single effective admin path, not a supported two-admin mutation model, so concurrent admin-change convergence is outside current scope. |
| SC-014 | Security, Correctness, and Convergence | Conflicting add/remove of same member converges deterministically | Unsupported | sequential remove/re-add behavior exists, but the exact two-admin conflicting add/remove case is outside the current single-effective-admin product contract. |
| UX-002 | Metadata, Notifications, and Optional Feature Coverage | Group rename | Unsupported | group rename is not surfaced after creation in the landed product, so this row should remain explicit unsupported scope. |
| UX-003 | Metadata, Notifications, and Optional Feature Coverage | Group picture/description update | Unsupported | avatar, photo, and description editing are not a shipped post-creation workflow here, so this row remains unsupported scope. |
| UX-004 | Metadata, Notifications, and Optional Feature Coverage | Mute notifications per group | Unsupported | there is no app-layer per-group mute flow or UI in the current product, so this row should close as unsupported scope. |
| UX-011 | Metadata, Notifications, and Optional Feature Coverage | Admin demotion / revoke admin | Unsupported | admin promotion and demotion are not shipped role-management flows in this product, so this row should remain unsupported scope. |
| UX-012 | Metadata, Notifications, and Optional Feature Coverage | Invite accept / decline / expiry | Unsupported | invites are auto-processed on receipt with no accept, decline, or expiry state machine, so this row is outside the landed product contract. |
| UX-014 | Metadata, Notifications, and Optional Feature Coverage | Group dissolve / deletion | Unsupported | the product supports leaving or local deletion, not an admin-initiated group dissolve workflow, so this row should remain explicit unsupported scope. |
