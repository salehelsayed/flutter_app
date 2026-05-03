# IJ-005 Invite Reuse Policy and Replay Protection

Status: execution-ready

## Session classification

Classification: `implementation-ready / needs_code_and_tests`

Pipeline mode: implementation-committed gap-closure

Source row: `IJ-005 | Invite reuse policy and replay protection`

Completed/Covered dependencies already recorded: `GL-005`, `LP-002`, `LP-003`, `LP-013`, `IJ-001`, `IJ-002`, `IJ-003`.

## Planning verdict

IJ-005 remains implementation-ready because the app already has receiver-local invite-consumption tombstones and direct signed invite plumbing, but it does not yet carry an explicit signed/encrypted reuse policy or tests that distinguish single-use and multi-use direct invite replay behavior.

This plan closes the direct signed invite credential portion of IJ-005. It does not claim first-class link invite creation/claim or shared account-wide cross-device consumption, because no link-token surface or account/device/shared consumption primitive exists in the obvious invite code. Those remain prerequisite-owned residuals, not blockers for closing direct invite credential reuse/replay.

Implementation must preserve:

- `IJ-001` encrypted-only policy privacy.
- `IJ-002` signed invite attestation.
- `IJ-003` invite revocation behavior.

Do not claim `TP-SMOKE-01`, `IJ-009`, `IJ-010`, `IJ-013`, or `EK-004`.

## Evidence Used

- `GroupInvitePolicy` currently has `expiresAt`, `allowedDevices`, `assignedRole`, `canInviteOthers`, `joinMaterialKind`, and `keyEpoch`; it has no reuse policy fields.
- `GroupInvitePayload` signs `invitePolicy` inside encrypted plaintext; the cleartext v2 invite envelope omits policy.
- `accept_pending_group_invite_use_case.dart` checks local consumption before accept and records local `GroupInviteConsumption` on success and bridge-degraded accept.
- `storeIncomingPendingGroupInvite` checks local consumption before pending storage.
- Migration `056` and receiver-local `group_invite_consumptions` tombstones exist.
- Repository tests prove consumption persistence and cleanup.
- Accept tests prove success and bridge-degraded accepts record consumption, and stale already-used pending rows fail before state/join.
- Store tests prove delayed consumed invite copies do not recreate pending state.
- No link-token model or shared server/device consumption sync exists in the obvious invite code.

## Scope Classification

| Surface | IJ-005 classification | Required disposition |
| --- | --- | --- |
| Single-use policy | Implementation-owned IJ-005 gap | Add a signed/encrypted invite policy field and enforce it with the existing receiver-local consumption tombstone. |
| Multi-use policy | Implementation-owned for explicit direct-invite semantics | Represent reusable direct credentials where allowed, without creating duplicate group membership. |
| Same-device replay | Implementation-owned | Enforce deterministic already-used or duplicate behavior before state side effects. |
| Expiry | Implementation-owned | Existing policy expiry remains, but IJ-005 needs replay/reuse tests proving expired credentials fail before state side effects. |
| Link invites | Prerequisite-owned/product-scope unsupported | Keep first-class link invite creation/claim out of this implementation if no link-token surface exists. Direct signed invite credential closure is not blocked. |
| Cross-device shared consumption | Prerequisite-owned by `IJ-013`/device/shared-state dependency | Require local allowed-device/policy tests and no duplicate or unauthorized membership for the same receiver device; do not claim shared account-wide enforcement. |

## Real Scope

Implement the smallest direct-invite behavior change:

1. Extend `GroupInvitePolicy` with a signed/encrypted reuse policy field, for example `reusePolicy`, with modes such as `singleUse` and `multiUse`.
2. Derive the default direct invite policy as `singleUse` to preserve current semantics unless the caller explicitly requests `multiUse`.
3. Validate missing, unknown, empty, or contradictory reuse policy values fail closed during parse/send/store/accept.
4. Enforce `singleUse` through existing `GroupInviteConsumption` checks before storing pending state or accepting.
5. Define `multiUse` direct invite semantics narrowly: the credential may be replayed where policy allows, but replay must not create duplicate group membership, duplicate key rows, duplicate bridge join rows, or duplicate pending rows.
6. Preserve duplicate-group protection; `multiUse` is not a bypass for existing local membership checks.
7. Keep reuse policy private inside encrypted signed payload content; do not expose it in the cleartext invite envelope.

## Closure Bar

IJ-005 can be accepted only when all of the following are true:

- `GroupInvitePolicy` carries explicit `singleUse` and `multiUse` reuse policy semantics in signed/encrypted invite policy data.
- Direct sends default to `singleUse`.
- Explicit `multiUse` direct invite creation is supported by the send path and round-trips through payload/store/accept.
- Missing, unknown, empty, or contradictory reuse policy fails closed before unauthorized pending, group, key, or join side effects.
- Same-device replay of a consumed `singleUse` credential deterministically returns already-used behavior before state side effects.
- Replay of an expired credential fails closed before state side effects.
- `multiUse` replay does not create duplicate group membership, duplicate group keys, duplicate bridge joins, or duplicate pending rows.
- Direct credential replay from a different peer/device is rejected by existing recipient binding and `allowedDevices` policy before state side effects.
- `IJ-001`, `IJ-002`, and `IJ-003` privacy/signature/revocation behavior remains green.
- The IJ-005 source matrix row is updated from `Open` to `Covered` or `Closed` with exact test evidence.
- The IJ-005 test-inventory row is updated from `Partial` to `Covered` or `Closed` with exact test evidence and residual notes for link invites/shared cross-device enforcement.

## Implementation Steps

1. Add a typed reuse policy model.
   - Add a `reusePolicy` field to `GroupInvitePolicy`.
   - Use explicit modes such as `singleUse` and `multiUse`.
   - Add bounded optional use-limit semantics only if they are simple, local, and directly testable; otherwise defer limits.
   - Make missing, unknown, malformed, or contradictory values fail closed in parsing and validation.

2. Keep the reuse policy signed and encrypted.
   - Serialize the new field inside `invitePolicy`.
   - Ensure `GroupInvitePayload` signs the updated `invitePolicy`.
   - Keep the cleartext v2 envelope free of policy internals, signed payloads, signatures, keys, member lists, peer addresses, and history.

3. Update send-path policy construction.
   - Default direct invite creation to `singleUse`.
   - Add the narrow caller/test path needed to request `multiUse`.
   - Validate unsupported link-like modes fail closed instead of inventing link semantics.

4. Update store-path replay handling.
   - For `singleUse`, keep checking existing `GroupInviteConsumption` before creating pending state.
   - For `multiUse`, do not reject solely because a local consumption tombstone exists, but still enforce signature, expiry, recipient binding, revocation, allowed-device policy, and duplicate-group protection.

5. Update accept-path replay handling.
   - Parse enough policy to distinguish reuse mode before applying the consumption check.
   - For `singleUse`, preserve already-used rejection before group/key/join side effects.
   - For `singleUse`, continue recording `GroupInviteConsumption` on success and bridge-degraded accept.
   - For `multiUse`, avoid recording single-use consumption and rely on duplicate local membership protection after the first successful accept.

6. Add RED tests before production code.
   - Cover payload policy parsing/signing/privacy.
   - Cover send defaults and explicit `multiUse`.
   - Cover store replay and accept replay.
   - Cover expiry and different-device recipient/allowed-device rejection.
   - Cover integration replay without pending/group duplication.

7. Update closure docs after green evidence.
   - Update only the IJ-005 source matrix and test-inventory rows required by this session.
   - Record link invites and shared cross-device consumption as prerequisite-owned residuals.

## RED Tests First

Add failing tests first, then run exactly:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

Required RED coverage:

- `singleUse` and `multiUse` reuse policy round-trip inside encrypted signed payload data.
- Reuse policy is not exposed in the cleartext v2 envelope.
- Missing/unknown/contradictory reuse policy fails closed.
- Direct sends default to `singleUse`.
- Direct sends can explicitly request `multiUse`.
- Consumed `singleUse` replay cannot recreate pending state or accept side effects.
- `multiUse` replay does not create duplicate local membership or duplicate join/key rows.
- Expired replay fails before pending/group/key/join side effects.
- Direct replay to a different peer/device fails by recipient/allowed-device policy.

## Green Gates

Run format on touched files:

```bash
dart format <touched Dart files>
```

Run the RED command again and require it to pass:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

Run invite application coverage:

```bash
flutter test --no-pub test/features/groups/application/*invite*_test.dart
```

Run onboarding regression coverage:

```bash
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Run the groups gate:

```bash
./scripts/run_test_gates.sh groups
```

Run the group integration directory:

```bash
flutter test --no-pub test/features/groups/integration
```

Run diff whitespace validation:

```bash
git diff --check
```

Supporting only when the real-network environment is configured:

```bash
./scripts/run_test_gates.sh group-real-network-nightly
```

If the real-network environment is unset, record `group-real-network-nightly` as unconfigured and non-blocking for IJ-005.

## Scope Guard

Do not implement or claim:

- Public invite URL parsing.
- QR/link invite UX.
- Link-token creation, storage, routing, redemption, or relay-backed claim flows.
- Shared account/device registry.
- Shared cross-device consumption sync.
- Relay-enforced invite use counters.
- Global invite quotas.
- `IJ-009` auto-join behavior.
- `IJ-010` concurrent join convergence.
- `IJ-013` account/device registry or richer multi-device eligibility.
- `EK-004` broad event-family signature parity.
- `TP-SMOKE-01` as IJ-005 closure evidence.

Do not expose reuse policy or invite policy internals in cleartext. Do not bypass existing duplicate-group, revocation, expiry, recipient binding, allowed-device, or signature checks.

## Residual Non-Goals

First-class link invite creation and claim remain prerequisite-owned or product-scope unsupported until a real link-token surface exists. This IJ-005 plan closes direct signed invite credential reuse/replay only.

Shared cross-device single-use enforcement remains prerequisite-owned by `IJ-013` or a future device/shared-state layer. Receiver-local tombstones can enforce same-device replay and can combine with recipient/allowed-device binding to reject direct credential replay by another peer/device, but they cannot claim account-wide consumption across independent repositories.

Multi-use in this plan means explicit direct invite credential reuse semantics in the current private invite architecture. It does not mean public reusable links.

## Reviewer And Arbiter

Reviewer verdict: sufficient for implementation as a direct signed invite credential gap-closure plan.

Reviewer notes:

- The plan includes the required model, payload, send, store, accept, and integration coverage.
- Link invites are correctly residual because no link-token surface exists in the obvious invite code.
- Shared cross-device consumption is correctly residual because no account/device/shared-state primitive exists.
- The RED command is bounded to the direct IJ-005 test surface.
- Green gates include focused tests, group gate, integration directory, formatting, and diff validation.

Arbiter verdict: no structural blocker remains.

Accepted differences:

- Link invites stay out of scope.
- Shared account-wide consumption stays out of scope.
- `group-real-network-nightly` is supporting-only and non-blocking when unconfigured.

## Execution Progress

- `2026-05-01 03:42:43 CEST` - Contract extracted: local sequential fallback in use because no nested child-agent spawn tool is available in this execution context; scope is direct signed invite credential reuse/replay only. Inspected `group_invite_policy.dart`, `group_invite_payload.dart`, `send_group_invite_use_case.dart`, `handle_incoming_group_invite_use_case.dart`, `accept_pending_group_invite_use_case.dart`, and invite tests. Next action: add RED IJ-005 tests before production implementation.
- `2026-05-01 03:48:04 CEST` - RED tests added in `group_invite_payload_test.dart`, `send_group_invite_use_case_test.dart`, `store_pending_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, and `invite_round_trip_test.dart`. RED command failed as expected: `GroupInviteReusePolicy` is undefined, `GroupInvitePolicy.reusePolicy` is missing, and `sendGroupInvite(reusePolicy: ...)` is unsupported. Next action: implement typed signed/encrypted reuse policy and policy-aware store/accept replay behavior.
- `2026-05-01 03:53:22 CEST` - Implementation completed for direct signed invite credential reuse policy: typed encrypted `reusePolicy`, default direct `singleUse` sends, fail-closed malformed/missing/unknown/contradictory policy parsing, same-device single-use tombstones, expiry-before-state rejection, recipient/allowed-device replay rejection when local peer identity is available, and explicit `multiUse` duplicate-safe replay semantics. Local QA found one compatibility issue in the invite wildcard gate where listener tests without `ownPeerId` were rejected through a `message.to` fallback; fixed by enforcing direct recipient binding only when the actual local peer id is provided, then reran focused and wildcard gates green.

## Execution Evidence

RED-first command before production implementation:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

Outcome: failed as expected with compile-time gaps: `GroupInviteReusePolicy` was undefined, `GroupInvitePolicy.reusePolicy` was missing, and `sendGroupInvite(reusePolicy: ...)` was unsupported.

Focused green command after implementation:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

Outcome: passed, `+81`.

Format checks:

```bash
dart format lib/features/groups/domain/models/group_invite_policy.dart lib/features/groups/application/send_group_invite_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/group_invite_listener.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
dart format lib/features/groups/application/handle_incoming_group_invite_use_case.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart
```

Outcome: passed. First run formatted 10 files with 4 changed; second run formatted 2 files with 0 changed.

Invite wildcard gate:

```bash
flutter test --no-pub test/features/groups/application/*invite*_test.dart
```

Outcome: initially failed on listener compatibility because recipient enforcement used the message envelope fallback when no `ownPeerId` was available. After the local fix, rerun passed, `+96`.

Onboarding gate:

```bash
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Outcome: passed, `+6`.

Groups gate:

```bash
./scripts/run_test_gates.sh groups
```

Outcome: passed, `+96`.

Group integration directory:

```bash
flutter test --no-pub test/features/groups/integration
```

Outcome: passed, `+118`.

Diff whitespace validation:

```bash
git diff --check
```

Outcome: passed with no output.

Supporting real-network gate:

```bash
./scripts/run_test_gates.sh group-real-network-nightly
```

Outcome: supporting-only and unconfigured, non-blocking for IJ-005. The gate failed immediately with `FLUTTER_DEVICE_ID is required for Group Real-Network Nightly Gate.`

## Local QA Review

QA verdict: accepted.

Blocking issues remaining: none found in the IJ-005 direct invite reuse/replay scope.

Fix loop used: yes. The invite wildcard exposed an over-strict listener recipient-binding path when no local peer id was available; production code was adjusted to require actual `ownPeerId` for direct recipient enforcement, and focused plus wildcard gates were rerun green.

## Final Execution Verdict

Final verdict: accepted.

Executed with local sequential fallback because this environment does not expose nested child-agent spawn tools. The implemented and tested closure covers direct signed invite credential reuse/replay only. First-class link invite creation/claim and shared account-wide cross-device consumption remain residual/prerequisite-owned as defined by this plan.
