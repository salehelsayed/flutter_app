# Libp2p Group Chat: What Was Not Fully Implemented

This table contains the matrix rows that remain `Open`, `Partial`, or
`Contract-undefined` after the rollout. These are the journeys that are still
not fully closed in current repo evidence.

Source: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

Count: 1

`UX-013` was **reopened to `Partial` on 2026-06-16** (it had been prematurely
marked `Closed` on 2026-04-05). The same-user multi-device contract exists in
`lib/features/groups/domain/models/group_multi_device_policy.dart`, but runtime
convergence holds **only for devices that already materialized the group
locally**. A freshly restored second device hydrates no group state and no keys
(restore re-mints a fresh ML-KEM keypair, so prior group-key distributions are
undecryptable) and silently drops incoming group messages. Mute / unread /
notifications / pending-invite review correctly stay installation-local.

| ID | Journey | Status | Why still open |
|---|---|---|---|
| UX-013 | Multi-device state convergence | Partial / Device-local-only | No production hydration path for a freshly restored second device; ML-KEM key re-mint on restore severs old group keys; the prior convergence "proof" only hand-copies repository rows. Shared-across-devices is aspirational until the Part B build (sibling-device admission + restore-time key continuity + peer hydration) ships behind `kMultiDeviceSyncEnabled` and is device-matrix verified. Tracked in `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/12-P2-multi-device-honesty.md`. |
