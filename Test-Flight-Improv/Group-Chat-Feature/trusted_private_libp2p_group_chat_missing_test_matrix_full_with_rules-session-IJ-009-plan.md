# IJ-009 Open Auto-Join Disabled for Trusted-Private Groups

Status: execution-accepted

## Planning Progress

- 2026-05-01 04:24:00 CEST - Arbiter completed. Files inspected since last update: IJ-009 source matrix row, IJ-009 breakdown row, `test-inventory.md`, `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, `join_group_use_case.dart`, `group_invite_payload.dart`, `group_invite_policy.dart`, direct invite/listener tests, `lib/main.dart`, and `scripts/run_test_gates.sh`. Decision/blocker: no structural blocker remains; this is implementation-ready because direct invite materialization and listener storage still need explicit current-own-peer binding before they can be treated as closed. Next action: execute RED-first tests, patch only identity-bound invite handling if RED exposes the expected gap, then run the listed gates.
- 2026-05-01 04:22:00 CEST - Reviewer completed; Arbiter started. Files inspected since last update: drafted plan sections and current listener/main wiring. Decision/blocker: plan is sufficient after tightening scope to direct signed invite credentials and rejecting local identity unavailable/mismatched paths before pending/group/key/join state. Next action: record accepted differences and final execution contract.
- 2026-05-01 04:20:00 CEST - Planner completed; Reviewer started. Files inspected since last update: current predecessor IJ-001/IJ-002/IJ-003/IJ-005 closure notes and invite tests. Decision/blocker: existing signed policy/revocation/reuse evidence stays accepted; IJ-009 owns only missing auto-join denial and local identity-binding proof. Next action: review for scope creep and missing gates.
- 2026-05-01 04:13:58 CEST - Evidence Collector completed; Planner started. Files inspected since last update: source breakdown IJ-009 rows, source matrix IJ-009 row, `test-inventory.md` IJ predecessor rows, `test-gate-definitions.md`, `scripts/run_test_gates.sh`, `accept_pending_group_invite_use_case.dart`, `join_group_use_case.dart`, `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, `group_invite_payload.dart`, `group_invite_policy.dart`, `group_invite_auth.dart`, `send_group_invite_use_case.dart`, `pending_group_invite_repository_impl.dart`, direct invite tests, and `lib/main.dart` listener wiring. Decision/blocker: current invite model rejects unsigned/missing-policy/stale/revoked/replayed direct paths, but listener/main and direct materialization still need current-own-peer binding tests. Next action: draft an execution-ready RED-first plan with a minimal code-only-if-RED stop point.
- 2026-05-01 04:11:39 CEST - Evidence Collector started. Files inspected since last update: `implementation-plan-orchestrator/SKILL.md`, `git status --short`, target plan path existence check. Decision/blocker: target plan did not exist; created live planning artifact; dirty worktree contains many unrelated/predecessor-session edits that must not be reverted. Next action: inspect source breakdown row, current invite/membership code, direct tests, and gate definitions.

## Execution Progress

- 2026-05-01 04:19:14 CEST - Executor contract extracted. Files inspected: this plan, `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, `lib/main.dart`, focused invite/listener tests, and `git status --short`. Decision/blocker: proceed with IJ-009 only; dirty worktree has unrelated/predecessor changes that must be preserved. Next action: add RED-first tests for missing/mismatched local peer identity before production edits.
- 2026-05-01 04:21:15 CEST - RED focused command finished. Files touched: IJ-009 focused direct handler, pending storage, and listener tests. Command: `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart`. Result: failed as expected (`+54 -3`); observed signature includes missing local peer identity returning `success` in direct handler and allowing state paths before the new fail-closed assertions. Next action: patch resolver identity binding, production listener wiring, and valid test call sites.
- 2026-05-01 04:25:05 CEST - Executor patch applied and focused green check completed. Files touched: `handle_incoming_group_invite_use_case.dart`, `lib/main.dart`, focused IJ-009 tests, and `invite_round_trip_test.dart` valid identity call sites. Command: `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart`. Result: passed (`+57`). Next action: run required format check and remaining green gates.
- 2026-05-01 04:28:00 CEST - Controller-side verification recovery completed after spawned Executor no-result shutdown. Files inspected: IJ-009 plan, landed diffs, `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, `lib/main.dart`, focused tests, and changed integration tests. Decision/blocker: landed seam is coherent and in scope; `lib/main.dart` now passes persisted identity peer id to `GroupInviteListener`; no blocking issue found. Next action: record final execution verdict.
- 2026-05-01 04:28:00 CEST - Required gates completed. Commands: format check passed (`Formatted 9 files (0 changed)`); focused direct/listener command passed (`+57`); accept/join preservation passed (`+19`); application invite wildcard passed (`+100`); `invite_round_trip_test.dart` passed (`+14`); `group_membership_smoke_test.dart` passed (`+23`); `./scripts/run_test_gates.sh groups` passed (`+96`); `git diff --check` passed. Supporting `group-real-network-nightly` was attempted and failed only because `FLUTTER_DEVICE_ID` is unset. Next action: closure audit can update IJ-009 source docs to `Covered`.

## Final Execution Verdict

Final verdict: `accepted`

Spawned-agent isolation used: yes. The spawned Executor produced code/test/plan progress but did not return after the bounded wait extension and was shut down; controller-side verification recovery was used for the QA review and remaining required gates.

Local sequential fallback used: controller-side verification recovery only after no-result child shutdown.

Files changed for IJ-009:

- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/main.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/store_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- preservation call-site updates in `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` and `test/features/groups/integration/invite_round_trip_test.dart`

Tests added or updated:

- IJ-009 direct handler test rejects signed invites when local peer identity is unavailable before group/key/join state.
- IJ-009 pending-store test rejects missing and mismatched local peer identity before pending/group/key/join state.
- IJ-009 listener tests reject copied signed invites and identity-unavailable invites before pending stream, pending row, group/key, or join state.
- Existing valid invite tests now supply the current expected local peer id instead of relying on absent identity.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: first-class link invite creation/claim remains out of scope until a link-token surface exists; shared account/device semantics remain IJ-013/device/shared-state work; real-network nightly remains unconfigured locally.

## real scope

Close IJ-009 for trusted-private group invites by proving that no automatic group admission occurs from copied, stale, link-shaped, or otherwise unbound join material unless the invite is a current signed invite bound to the local accepting peer identity.

Implementation may touch only the direct invite receive/materialization path, listener wiring, and tests needed to pass the row:

- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/main.dart`
- focused invite/listener/join tests under `test/features/groups/application/`
- preservation integration tests under `test/features/groups/integration/`

Do not add public rooms, link invite creation, link claim, join request workflows, shared account-wide device consumption, or concurrent join convergence.

## closure bar

IJ-009 is closed when focused tests prove all of the following:

- a valid-looking signed invite copied to a different local peer is rejected before pending invite, group, member, key, join, or notification state
- a signed invite cannot be processed when the app cannot determine the current local peer identity
- direct `handleIncomingGroupInvite` cannot materialize group/key/member state without a local peer identity matching the invite recipient and allowed-device policy
- listener/main wiring supplies the current peer id so production listener handling can enforce the same binding
- stale, revoked, unsigned, bad-policy, and single-use replay protections from IJ-001/IJ-002/IJ-003/IJ-005 remain green

The source matrix row may move to `Covered` only after the source row, `test-inventory.md`, and this breakdown record concrete code/test evidence.

## source of truth

Authoritative:

- source matrix row IJ-009 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- row 9 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- current code in `handle_incoming_group_invite_use_case.dart`, `group_invite_listener.dart`, `group_invite_payload.dart`, and `lib/main.dart`
- current focused invite tests
- `scripts/run_test_gates.sh groups`

Current code/tests beat stale broad matrix prose. Predecessor rows IJ-001, IJ-002, IJ-003, and IJ-005 are accepted evidence and must not be reopened except as preservation tests.

## session classification

`implementation-ready`

The original breakdown classified IJ-009 as `needs_tests_only`, but evidence shows a row-owned implementation gap: direct invite resolution accepts valid signed invites without a known local peer id, and production `GroupInviteListener` in `lib/main.dart` currently does not pass `getOwnPeerId`. This is an implementation-owned gap inside the IJ-009 owner files.

## exact problem statement

Trusted-private groups must not have an open auto-join path. Today signed, policy-valid invite payloads are strong enough to reject tampering, revocation, expiry, and replay, but the receive/materialization path can still be called without an explicit current local peer id. If a valid invite for Bob is copied to another local profile and that code path lacks local identity, the payload can be treated as valid before the app proves it belongs to the accepting peer.

The required behavior is fail-closed: no pending invite, group row, member row, key row, `group:join`, or user notification state may be created unless the current local peer id is known and matches both `recipientPeerId` and `invitePolicy.allowedDevices`.

## files and repos to inspect next

Production:

- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/main.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_policy.dart`
- `lib/features/groups/application/join_group_use_case.dart`

Tests:

- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/store_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/join_group_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## existing tests covering this area

Existing accepted coverage:

- IJ-001 tests require first-class encrypted invite policy and reject missing/contradictory policy before state.
- IJ-002 tests require signed invite attestation, trusted-contact verification, and inviter authorization.
- IJ-003 tests reject revoked delayed direct/mailbox copies and revoked accept attempts.
- IJ-005 tests reject consumed single-use copies, expired invites, malformed reuse policy, and duplicate multi-use side effects.
- Existing listener tests prove valid invites are stored as pending and do not call `group:join`.
- Existing direct handler tests prove wrong recipient is rejected when `ownPeerId` is explicitly supplied.

Missing before IJ-009:

- no test proves direct handler/store paths fail closed when `ownPeerId` is missing
- no test proves listener rejects copied signed invites when local identity is unavailable or mismatched
- production `GroupInviteListener` construction in `lib/main.dart` does not pass `getOwnPeerId`

## regression/tests to add first

Add RED-first tests before production edits:

1. In `handle_incoming_group_invite_use_case_test.dart`, add `IJ009 rejects signed invite when local peer identity is unavailable before state or join`. Call `handleIncomingGroupInvite` with a valid signed v1/v2 invite and no `ownPeerId`; expect `invalidPayload`, no group, no key, and no `group:join`.
2. In `store_pending_group_invite_use_case_test.dart`, add `IJ009 does not store pending invite when local peer identity is unavailable or mismatched`. Use a valid signed invite; first call without `ownPeerId`, then with a different `ownPeerId`; expect `invalidPayload`, no pending, no group, no key, and no `group:join`.
3. In `group_invite_listener_test.dart`, add `IJ009 rejects copied signed invite before pending or notification state when local identity differs`. Build a signed v2 invite for Bob, run a listener whose `getOwnPeerId` returns Eve, and assert no pending stream event, no pending row, no group/key, and no `group:join`.
4. In `group_invite_listener_test.dart`, add a fail-closed identity-unavailable listener case if current constructor allows omission/empty identity. Expect no pending event or state.

The initial RED command should run only these focused invite/listener files. The expected pre-fix failure is that missing local identity still permits direct materialization or pending storage.

## step-by-step implementation plan

1. Add the RED tests above and run the focused command:
   `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart`
2. If the RED tests already pass, stop production edits and treat IJ-009 as tests-only; otherwise patch only the observed gap.
3. In `handle_incoming_group_invite_use_case.dart`, require a non-empty `ownPeerId` before resolving any group invite payload for storage or direct materialization. Reject with `invalidPayload` before auth, pending save, materialization, or bridge join if `ownPeerId` is absent.
4. In the same resolver, require `payload.recipientPeerId == ownPeerId` and `payload.invitePolicy.allowedDevices.contains(ownPeerId)` before returning success.
5. Update valid existing direct/store/listener tests to pass the expected local peer id instead of relying on absent identity.
6. In `lib/main.dart`, pass `getOwnPeerId` into the production `GroupInviteListener` from persisted identity, matching the existing `IntroductionListener` pattern.
7. Keep `join_group_use_case.dart` unchanged unless tests prove it is reachable from token/link/open-join UI; current repo evidence shows no production callers.
8. Run focused tests, invite wildcard, integration preservation, groups gate, and `git diff --check`.

## risks and edge cases

- Older unit tests may have used absent `ownPeerId` as a shortcut for valid direct invite handling; update tests to model the production trusted-private requirement instead of weakening the implementation.
- Do not fallback to `message.to` for invite identity checks. A predecessor IJ-005 fix intentionally avoided using transport `to` as local identity when the app does not know its own peer id.
- Requiring local identity must reject before pending/group/key/join side effects.
- Expired, revoked, already-used, unsigned, and tampered invites must keep their existing result semantics.
- Valid listener invite flow must still store pending and avoid auto-join when `getOwnPeerId` returns the intended recipient.

## exact tests and gates to run

RED focused command:

```sh
flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart
```

Green verification:

```sh
dart format --output=none --set-exit-if-changed lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/group_invite_listener.dart lib/main.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/*invite*_test.dart
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

Supporting only:

```sh
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

This nightly gate is not blocking when local device/relay env is unset.

## known-failure interpretation

- `group-real-network-nightly` is supporting-only unless the needed device and relay environment variables are configured.
- Existing unrelated broad-suite failures from previous sessions must not be classified as IJ-009 regressions unless they touch the files changed by this session or the focused IJ-009 gates.
- Any failure in focused invite/listener/direct handler tests is blocking for IJ-009.
- `join_group_use_case_test.dart` remains a low-level join helper preservation check; it should not be reinterpreted as approval for public/open auto-join UI.

## done criteria

- RED evidence is recorded in this plan with the failing command and failure signature.
- Production rejects invite resolution when local peer identity is unavailable or mismatched.
- Production `GroupInviteListener` is wired with `getOwnPeerId`.
- Focused IJ-009 tests pass and prove no pending/group/member/key/join/notification state for copied or identity-unavailable invites.
- Invite predecessor tests and groups gate remain green.
- Source matrix row IJ-009, `test-inventory.md`, and the session breakdown are updated to `Covered` with concrete evidence by closure.
- `git diff --check` passes.

## scope guard

Do not implement:

- public rooms
- open join
- link invite creation or link claim
- join request moderation
- shared account-wide multi-device consumption
- IJ-010 concurrent join convergence
- IJ-013 first-class device identity model
- EK-004 broad event-family signature parity
- transport protocol or Go/libp2p changes

Do not weaken signed invite, revocation, replay, or policy validation to preserve old tests.

## accepted differences / intentionally out of scope

- Existing direct invite credentials remain the only invite surface in scope. First-class link-token creation/claim is not present and remains product-scope/prerequisite-owned until a link-token surface exists.
- Device-specific account-wide binding remains IJ-013/device/shared-state work. IJ-009 only requires current local peer id binding for trusted-private direct invites.
- The low-level `joinGroup` helper is not a user-facing open auto-join path because the repo has no production callers; it remains a preservation test surface unless execution discovers a real caller.

## dependency impact

- IJ-010 concurrent joins should build on IJ-009's fail-closed identity-bound admission, but IJ-009 does not prove convergence.
- IJ-013 should build richer device binding on top of this local peer binding, but IJ-009 does not close device registry semantics.
- TP-SMOKE-01 can use IJ-009 as supporting evidence but is not itself a source row closure.
