# IJ-001 Invite Payload Completeness and Privacy Plan

Status: accepted with non-blocking caveat

## Planning Progress

- `2026-04-30T23:11:10Z` - Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, `git status --short`, missing intended plan path check. Decision/blocker: IJ-001 source row and plan path confirmed; worktree has unrelated accepted dirty changes that must not be overwritten. Next action: collect row, inventory, breakdown, code, test, and gate evidence before drafting.
- `2026-04-30T23:13:24Z` - Evidence Collector completed; Planner started. Files inspected since last update: IJ-001 source row, inventory crosswalk, session breakdown, `test-gate-definitions.md`, `scripts/run_test_gates.sh`, invite production files, direct invite tests, pending invite model/repository, and send call sites. Decision/blocker: current code preserves policy-like keys only as ad hoc encrypted `groupConfig` data; no first-class invite policy or rejection path exists for missing/contradictory device, permission, expiry, or join-material policy. Next action: draft an implementation-ready, tests-first plan with the smallest IJ-001-owned policy fix.
- `2026-04-30T23:15:29Z` - Planner completed; Reviewer started. Files inspected since last update: no new files; planner synthesized evidence already collected. Decision/blocker: draft classification is `implementation-ready / needs_code_and_tests` because code needs a first-class encrypted invite policy and fail-closed validation before IJ-001 can close. Next action: review the plan for scope drift, missing tests/gates, stale assumptions, and dependency bleed.
- `2026-04-30T23:17:27Z` - Reviewer completed; Arbiter started. Files inspected since last update: draft plan artifact only. Decision/blocker: plan is sufficient with one tightening applied: receive-path invalid-policy proof must cover both pending-store and direct-handle paths, not either/or. Next action: arbitrate reviewer findings into blockers, incremental details, and accepted differences.
- `2026-04-30T23:18:07Z` - Arbiter completed. Files inspected since last update: reviewed plan artifact only. Decision/blocker: no structural blockers remain; plan is execution-ready with code-and-test ownership limited to first-class invite policy completeness/privacy. Next action: hand off to implementation without touching source matrix, inventory, or breakdown ledger in this planning pass.

## real scope

IJ-001 owns the invite payload contract for trusted-private group invites:

- Direct and inbox-fallback invites must carry enough encrypted data for the intended invitee to evaluate and accept the group: preview identity, expiration, device allowance, assigned invite permissions, join-material reference, `groupKey`, `keyEpoch`, and current group config/member key material needed by the current architecture.
- The cleartext v2 envelope must remain preview/routing only: `type`, `version`, invite id, sender peer/user preview, group id, group name, and the `encrypted` block. It must not expose member lists, group keys, member public keys, ML-KEM keys, peer addresses, history text, `allowedDevices`, `invitePermissions`, `joinMaterialRef`, or the new first-class invite policy.
- Missing or contradictory first-class invite policy must fail before pending storage, group/key state creation, bridge `group:join`, or direct/inbox send success is reported.

IJ-001 does not own signed inviter authorization, revocation delivery, replay/reuse policy, open auto-join, concurrent join convergence, full account/device registry semantics, real-network device-lab proof, or broader history sync policy.

## closure bar

The row can move from `Partial` to `Covered`/`Closed` only when focused tests prove all of the following in the current repo:

- New sends generate a first-class encrypted invite policy, not ad hoc policy keys hidden inside `groupConfig`.
- The encrypted policy includes expiration, current recipient allowance, invite permissions, and join-material reference tied to the actual `groupKey`/`keyEpoch`.
- The direct and inbox fallback envelopes expose only safe preview/routing fields outside `encrypted`.
- Receive, pending-store, and accept paths reject missing or contradictory policy before creating group rows, key rows, pending rows where applicable, bridge joins, notifications, or history access.
- Existing direct invite, pending invite, and invite round-trip behavior remains green after fixture updates.

## source of truth

Authoritative sources, in conflict order:

1. Current code and tests in `lib/features/groups/**` and `test/features/groups/**`.
2. `Test-Flight-Improv/test-gate-definitions.md`, with `scripts/run_test_gates.sh` winning if the gate doc and script disagree.
3. IJ-001 source row in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
4. Current `test-inventory.md` IJ-001 crosswalk.
5. Session breakdown rows for IJ-001.

The breakdown currently labels IJ-001 `needs_tests_only`, but current code and inventory evidence show a real behavior gap: policy-like fields are only arbitrary `groupConfig` keys in one test and are not first-class payload policy with validation. Current code wins over the provisional breakdown label.

## session classification

`implementation-ready / needs_code_and_tests`.

Code changes are expected. This is not acceptance-only, doc-only, or tests-only while IJ-001 remains `Partial`.

## exact problem statement

IJ-001 is still partial because invite policy is not an explicit contract. `GroupInvitePayload` serializes `groupKey`, `keyEpoch`, `groupConfig`, sender metadata, timestamp, and optional `recipientPeerId`, but it has no first-class policy field for expiration, allowed devices, invite permissions, or join-material reference. `send_group_invite_use_case_test.dart` proves policy-like keys can be placed inside encrypted `groupConfig`, but production parsing does not require those keys and no receive/accept path rejects missing or contradictory policy.

User-visible risk: an invite can look valid, be stored or accepted, and create local group/key state even when the receiver cannot reliably know whether the invite is expired, whether this recipient/device is allowed, what role/permissions are being granted, or whether the join material matches the advertised key epoch.

Must stay unchanged: v2 invite transport remains encrypted; preview stays safe; direct send still falls back to inbox; existing pending expiration, duplicate group, revocation, consumption, unknown sender, sender mismatch, recipient mismatch, and missing join-material guards keep their semantics.

## files and repos to inspect next

Production files:

- `lib/features/groups/domain/models/group_invite_payload.dart`
- Add or colocate a narrow model such as `lib/features/groups/domain/models/group_invite_policy.dart` only if it reduces complexity versus embedding map validation in `GroupInvitePayload`.
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`
- Call-site compile check only: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`

Direct tests:

- `test/features/groups/domain/models/group_invite_payload_test.dart`
- `test/features/groups/domain/models/pending_group_invite_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/store_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`

Infra/config:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Already covered:

- `send_group_invite_use_case_test.dart` proves v2 direct and inbox-fallback envelopes keep group key material, member key material, and the current ad hoc `allowedDevices`, `invitePermissions`, and `joinMaterialRef` keys inside encrypted content.
- `group_invite_payload_test.dart` proves current required-field parsing for `groupId`, `groupKey`, `keyEpoch`, `groupConfig`, sender, username, and timestamp.
- `pending_group_invite_test.dart` proves pending preview fields and local TTL expiry are derived from payload/config.
- `store_pending_group_invite_use_case_test.dart` proves validated pending storage, duplicate group rejection, unknown sender rejection, revoked invite tombstone rejection, and consumed invite tombstone rejection.
- `handle_incoming_group_invite_use_case_test.dart` proves sender mismatch, unknown sender, recipient mismatch, missing `groupKey`, empty `groupKey`, missing `groupConfig`, materialization, member persistence, key persistence, and bridge `group:join`.
- `accept_pending_group_invite_use_case_test.dart` proves expired pending invites are removed, missing join material stays pending for repair without group/key state, and revoked/used invites fail before joining.
- `invite_round_trip_test.dart` proves v2 invite round trips and post-join history boundaries.
- `group_new_member_onboarding_test.dart` proves new-member onboarding/history limits independent of invite policy shape.

Missing:

- No test requires a first-class invite policy field.
- No test rejects an invite whose policy is missing while the rest of the payload is valid.
- No test rejects contradictory policy, such as a join-material reference whose epoch does not match `keyEpoch`, an expiration that is already stale, an allowed-device/recipient allowance that excludes the bound recipient in the current peer-bound architecture, or invite permissions that contradict the recipient member role in `groupConfig`.
- No test proves pending `expiresAt` is derived from encrypted invite policy rather than only local receipt time.

## regression/tests to add first

Add failing tests before production edits:

1. `group_invite_payload_test.dart`: valid payload serializes and parses a first-class encrypted policy map:

   ```json
   {
     "invitePolicy": {
       "expiresAt": "2026-03-09T12:00:00.000Z",
       "allowedDevices": ["12D3KooWBob"],
       "invitePermissions": {
         "assignedRole": "writer",
         "canInviteOthers": false
       },
       "joinMaterialRef": {
         "kind": "inlineGroupKey",
         "keyEpoch": 1
       }
     }
   }
   ```

2. `group_invite_payload_test.dart`: parsing returns null for missing policy and for focused contradictions: empty/excluding `allowedDevices`, missing `invitePermissions.assignedRole`, `invitePermissions.assignedRole` not matching the recipient member role in `groupConfig`, missing `joinMaterialRef`, `joinMaterialRef.kind` not `inlineGroupKey`, `joinMaterialRef.keyEpoch` not equal to payload `keyEpoch`, missing/unparseable/stale `expiresAt`, or missing `recipientPeerId`.
3. `send_group_invite_use_case_test.dart`: direct and inbox fallback v2 envelopes expose only safe preview/routing fields in cleartext and carry `invitePolicy`, `groupKey`, `keyEpoch`, and full group/member key material only inside encrypted plaintext.
4. `send_group_invite_use_case_test.dart`: invalid derived or override policy returns a new `SendGroupInviteResult.invalidPayload` failure result before `callEncryptMessage`, `sendMessage`, or `storeInInbox`.
5. `store_pending_group_invite_use_case_test.dart`: a decrypted invite missing/contradicting first-class policy returns `invalidPayload` and creates no pending/group/key state.
6. `handle_incoming_group_invite_use_case_test.dart`: a direct-handle invite missing/contradicting first-class policy returns `invalidPayload` and creates no group/key state or bridge join.
7. `pending_group_invite_test.dart`: pending preview preserves safe fields and derives `expiresAt` from the encrypted invite policy, clamped no later than the local pending invite TTL if a sender advertises an excessively long expiry.
8. `accept_pending_group_invite_use_case_test.dart`: an existing pending row with invalid policy returns `repairPending`, leaves the row available for repair, and creates no group/key state or bridge join.
9. `invite_round_trip_test.dart`: extend the focused v2 round trip or add one narrow test proving policy survives send -> decrypt/handle -> pending/accept while no pre-join history is exposed.

## step-by-step implementation plan

1. Add the failing tests listed above. Keep test names prefixed or worded with `IJ001` where useful so focused reruns are easy.
2. Add a minimal first-class invite policy representation. Prefer a small `GroupInvitePolicy` value object if it keeps validation clear; otherwise keep validation private to `group_invite_payload.dart`.
3. Extend `GroupInvitePayload` with required first-class policy for trusted-private invites. Serialization must place it in the inner payload for v2 and the v1 payload body for tests/legacy helpers, never in the cleartext v2 envelope.
4. Implement validation in one place and have both `fromInnerJson` and `fromJson` reject missing or contradictory trusted-private policy. Validation should check:
   - `recipientPeerId` is present and non-empty.
   - `expiresAt` parses and is after the payload timestamp.
   - `allowedDevices` is a non-empty string list and, for the current peer-bound architecture, contains `recipientPeerId`.
   - `invitePermissions.assignedRole` exists and matches the recipient's member role in `groupConfig.members`.
   - `invitePermissions.canInviteOthers` is boolean when present.
   - `joinMaterialRef.kind` is `inlineGroupKey`.
   - `joinMaterialRef.keyEpoch` equals payload `keyEpoch`.
   - existing `groupKey.trim().isNotEmpty` and `keyEpoch > 0` guards remain effective.
5. Update `sendGroupInvite` to build the policy before encryption. Derive default policy from existing inputs without widening call sites:
   - `expiresAt`: now plus the existing pending invite TTL.
   - `allowedDevices`: `[recipientPeerId]` in the current peer-bound architecture.
   - `invitePermissions.assignedRole`: the recipient member role from `groupConfig.members`.
   - `invitePermissions.canInviteOthers`: derive from member permissions/role if present; otherwise false for non-admin writer/member roles.
   - `joinMaterialRef`: `inlineGroupKey` with `keyEpoch`.
   Add `SendGroupInviteResult.invalidPayload` and return it before encryption/send if derivation fails.
6. Update `sendGroupInvitesInParallel` only as needed to propagate the new failure result and user-facing failure label. Do not change batching semantics.
7. Update `PendingGroupInvite.fromPayload` to use policy expiry for `expiresAt`, clamped to local TTL. Keep existing preview fields safe and do not copy policy details into preview columns beyond `payloadJson`.
8. Add receive-path expiry/policy rejection:
   - `storeIncomingPendingGroupInvite` rejects expired policy at `receivedAt` before saving pending state.
   - `handleIncomingGroupInvite` rejects invalid policy before materialization; add a test-only-friendly optional `now` only if needed for deterministic expiration checks.
   - `acceptPendingGroupInvite` continues to treat invalid pending payload as repair-pending with no group/key state.
9. Update direct fixture builders in invite tests to include valid policy. Avoid broad fixture refactors outside the invite test owners.
10. Run the exact tests/gates. If the tests prove existing behavior already covers one planned code step, skip that code step and keep the closure evidence narrow. If adding first-class policy requires product choices about multi-device identity, invite links, signatures, revocation, or replay policy, stop and record the dependency instead of inventing those features under IJ-001.

## risks and edge cases

- Existing helper fixtures without policy will fail once parsing requires first-class policy; update only invite-owned tests and helpers.
- Current code has no separate device-id registry. Treat `allowedDevices` as the current recipient peer/device binding for IJ-001, and do not design account-level multi-device policy here.
- Sender-advertised expiration must not extend local pending retention indefinitely; clamp to local TTL.
- Direct handle paths and pending-store paths must both reject invalid policy before group/key state mutation.
- Bridge failures after a valid accept should retain current behavior: persisted group/key state plus `bridgeError`.
- Privacy regression risk is high: tests must inspect the cleartext envelope after removing `encrypted`.
- Dirty worktree has accepted GL-005, LP-002, LP-003, and LP-013 changes; do not revert or restage unrelated docs, Go files, or group tests.

## exact tests and gates to run

Direct tests after adding the failing tests and implementation:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/pending_group_invite_test.dart
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/application/*invite*_test.dart
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Named and broad gates:

```bash
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
git diff --check
```

Device/relay supporting gate, only when the environment is configured:

```bash
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

Do not add Go tests for IJ-001 unless implementation unexpectedly changes Go bridge or libp2p invite transport behavior.

## known-failure interpretation

- Any failure in the direct invite tests, `invite_round_trip_test.dart`, `group_new_member_onboarding_test.dart`, or `./scripts/run_test_gates.sh groups` must be treated as IJ-001 blocking unless a clean baseline proves it pre-existed and is unrelated to invite payload policy/privacy.
- `group-real-network-nightly` requires configured `FLUTTER_DEVICE_ID` and relay addresses; missing configuration is not an IJ-001 implementation failure, but a run that starts and fails on invite payload behavior is blocking.
- Broad Go owner-suite failures already documented for LP-002/LP-003/LP-013 sender/transport peer-mismatch tests are unrelated unless IJ-001 changes Go files, which this plan does not require.
- Do not remove red tests from a gate to make IJ-001 appear green; follow `test-gate-definitions.md`.

## done criteria

- Plan-owned tests fail before implementation and pass after implementation.
- New first-class invite policy is present inside encrypted invite payloads for direct and inbox fallback.
- Cleartext envelopes remain preview/routing only.
- Missing/contradictory policy fails closed before pending/group/key state or bridge join.
- Existing invite send, pending, handle, accept, round-trip, and new-member onboarding tests pass.
- Required gates pass or have explicitly classified unrelated pre-existing failures.
- No non-IJ-001 source matrix, inventory, or breakdown closure docs are updated during implementation until the execution/closure agents do that work.

## scope guard

Non-goals:

- Do not implement IJ-002 signed invite authentication, inviter authorization, or stale inviter rejection.
- Do not implement IJ-003 revocation delivery/API or signed revocation envelopes.
- Do not implement IJ-005 reusable invite links, single-use versus multi-use policy, or cross-device consumption enforcement.
- Do not implement IJ-009 auto-join or token/link admission flows.
- Do not implement IJ-010 concurrent-join convergence or conflict resolution.
- Do not implement IJ-013 true account/device identity binding beyond the current recipient peer/device allowance field.
- Do not change Go/libp2p PubSub, rendezvous, relay, or peer scoring.
- Do not expose policy, keys, members, peer addresses, or history in cleartext preview.

Overengineering indicators:

- Adding a device registry, invite link protocol, signature chain, revocation protocol, replay ledger redesign, or membership convergence engine.
- Refactoring group config hashing, role update authorization, or unrelated pending invite storage layers without a failing IJ-001 test.
- Broad UI redesign of pending invite surfaces.

## accepted differences / intentionally out of scope

- Current app architecture uses peer identity as the available recipient/device binding in invite send paths. IJ-001 may encode this as `allowedDevices: [recipientPeerId]`; richer account/device modeling belongs to IJ-013.
- Signed inviter trust is intentionally not solved here; sender mismatch and known-contact checks remain existing coverage, while signed authorization belongs to IJ-002.
- Revoked, replayed, already-used, multi-use, and invite-link semantics belong to IJ-003 and IJ-005. IJ-001 may validate the presence and consistency of join material, but must not invent reuse policy.
- New-member history entitlement remains owned by IJ-011 and existing onboarding tests; IJ-001 only ensures the invite payload does not expose history beyond policy.
- Real-network/device-lab proof is supporting for IJ-001 while the row's required closure can be host tests plus group gate unless a direct policy bug appears only on device transport.

## dependency impact

- IJ-002 can later sign a stable first-class policy instead of arbitrary `groupConfig` extras.
- IJ-003 can later revoke policy-bearing invite ids without changing payload shape.
- IJ-005 can later add explicit reuse policy fields adjacent to the first-class invite policy rather than overloading `groupConfig`.
- IJ-009 and IJ-013 depend on fail-closed recipient/device allowance semantics; if IJ-001 cannot establish the current peer-bound allowance, those rows should not claim full device-bound safety.
- IJ-010 and IJ-011 should not be planned around invite payload ambiguity once IJ-001 is closed.

## reviewer pass

Reviewer verdict: sufficient with adjustments; the adjustment was applied in this plan.

Reviewer answers:

- Sufficiency: sufficient after tightening invalid-policy receive proof to require both pending-store and direct-handle tests.
- Missing files/tests/gates: no additional production owner beyond invite payload, send, pending, handle, and accept paths. `group_invite_listener_test.dart` is optional because listener behavior delegates to `storeIncomingPendingGroupInvite`; add it only if implementation changes listener logic.
- Stale assumptions: the breakdown's `needs_tests_only` label is stale for IJ-001 because current code has no first-class policy validation. Current code and inventory partial reason win.
- Overengineering: avoid adding device registry, signed invites, invite links, revocation protocol, replay policy, or Go transport changes.
- Decomposition: narrow enough if implementation starts with payload/policy tests and stops when policy validation is proven.
- Minimum needed: first-class encrypted policy, fail-closed validation, policy-derived pending expiry, and focused direct/integration tests.

## arbiter decision

Final arbiter classification:

- Structural blockers: none.
- Incremental details: `group_invite_listener_test.dart` may be added only if implementation changes listener behavior; otherwise direct store tests are enough because listener delegates to `storeIncomingPendingGroupInvite`.
- Accepted differences: current peer-bound `allowedDevices` semantics are sufficient for IJ-001 payload completeness/privacy; account-level multi-device policy remains IJ-013. Signed inviter auth, revocation, replay/reuse, auto-join, concurrent joins, and history entitlement remain separate rows.
- Stop rule: stop after this arbiter pass. Do not reopen accepted differences as IJ-001 implementation work.

## Execution Progress

- `2026-04-30T23:22:33Z` - Contract extracted; local sequential fallback started because nested Executor/QA spawning is unavailable in this isolated execution agent. Files inspected: orchestrator skill, this plan, `git status --short`, invite payload/pending/send/handle/accept/repository files, direct invite tests, and group config/member models. Decision/blocker: contract is concrete and safe to execute locally under fallback; unrelated accepted GL-005/LP-002/LP-003/LP-013 dirty files are outside IJ-001 and must be preserved. Next action: add IJ-001 regression tests first, then implement policy model and fail-closed paths.
- `2026-04-30T23:27:02Z` - RED tests added in local Executor fallback. Files touched: `group_invite_payload_test.dart`, `pending_group_invite_test.dart`, `send_group_invite_use_case_test.dart`, `store_pending_group_invite_use_case_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`. Decision/blocker: tests now assert first-class `invitePolicy`, policy-clamped pending expiry, send `invalidPayload`, and missing-policy fail-closed paths. Next action: run the first focused red test command, then implement the smallest policy model and validation changes.
- `2026-04-30T23:34:36Z` - Local Executor implementation pass completed. Files touched: added `group_invite_policy.dart`; updated invite payload parsing/serialization, pending expiry clamp, send invalid-payload guard, receive/store/direct/accept policy validation, and invite-owned fixtures/integration assertions. Commands completed: domain focused tests passed; application focused tests passed after one fixture-only correction for parallel recipients that were not in `groupConfig.members`. Next action: run remaining required direct tests and gates, then perform local QA review.
- `2026-04-30T23:37:06Z` - Required verification completed in local QA fallback. RED evidence: `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/pending_group_invite_test.dart` failed before production edits because `GroupInvitePolicy`/`invitePolicy` did not exist. Green evidence after implementation: domain focused tests passed (`+21`); application focused tests passed (`+57`); application invite glob passed (`+72`); `invite_round_trip_test.dart` passed (`+12`); `group_new_member_onboarding_test.dart` passed (`+6`); `./scripts/run_test_gates.sh groups` passed (`+94`); `flutter test --no-pub test/features/groups/integration` passed (`+116`); `git diff --check` passed with no output. Supporting device gate was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. Next action: finalize execution verdict.
- `2026-04-30T23:37:06Z` - Local QA review completed. Decision/blocker: accepted with a non-blocking caveat for the unconfigured supporting real-network device gate. No IJ-001 blocker remains; no closure-ledger, source-matrix, or test-inventory updates were made by this execution pass.

## Final Execution Verdict

Verdict: accepted with non-blocking caveat.

Non-blocking caveat: the supporting `group-real-network-nightly` gate was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset in this environment. This is explicitly supporting-only for IJ-001 and does not block the host-test closure evidence.

Scope completed:

- Added first-class `GroupInvitePolicy` and embedded it only in encrypted invite payload plaintext.
- Added fail-closed policy validation for parsing, send preflight, pending store, direct handle, materialization, and pending accept repair behavior.
- Derived pending invite expiry from encrypted policy expiry, clamped no later than local TTL.
- Preserved cleartext v2 envelopes as preview/routing only.
- Preserved accepted unrelated worktree edits outside IJ-001.

Commands recorded:

- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/pending_group_invite_test.dart` - failed before production edits as RED evidence, passed after implementation (`+21`).
- `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` - passed after one fixture-only correction (`+57`).
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart` - passed (`+72`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` - passed (`+12`).
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` - passed (`+6`).
- `./scripts/run_test_gates.sh groups` - passed (`+94`).
- `flutter test --no-pub test/features/groups/integration` - passed (`+116`).
- `git diff --check` - passed with no output.
