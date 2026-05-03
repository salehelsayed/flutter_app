# IJ-013 Session Plan - Wrong identity or device invite rejection

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T05:00:30+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; `handle_incoming_group_invite_use_case.dart`; `accept_pending_group_invite_use_case.dart`; `group_invite_payload.dart`; invite application tests | Existing receive/store/listener paths reject copied or wrong-recipient signed invites before pending/group/key/join state when current local peer identity is available. The remaining row-owned app gap is persisted pending accept: `acceptPendingGroupInvite` parses and validates the invite but does not re-check `recipientPeerId`/`allowedDevices` against the current local identity before materialization. | Draft a narrow accept-time identity-binding fix and focused regression. |
| 2026-05-01T05:01:20+02:00 | Planner completed | same | Add accept-time validation using the already supplied local `senderPeerId` identity, delete copied wrong-recipient pending rows, and prove no group/key/join/consumption/message side effects. Keep current Peer ID as the shipped identity/device binding unit. | Review closure scope and gates. |
| 2026-05-01T05:02:10+02:00 | Reviewer completed | same plus live device checks | Plan is sufficient if closure does not claim a separate first-class account/device registry. The device/relay proof is supporting only for IJ-013 because the direct row-owned gap is host-testable at the app layer. | Arbiter classification. |
| 2026-05-01T05:03:00+02:00 | Arbiter completed | same | execution-ready. Accepted difference: this session closes wrong identity/current-device binding for the shipped Peer ID invite contract; richer account/device registry and sibling-device approval remain outside IJ-013. | Implement focused accept-time guard and tests. |

## Execution Progress

| timestamp | phase | files inspected or touched | command / evidence | decision | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T05:05:00+02:00 | Contract extracted | `accept_pending_group_invite_use_case.dart`; `accept_pending_group_invite_use_case_test.dart`; session plan | Scope is a narrow accept-time identity guard plus focused regression; no new identity model or UI flow. | Safe to patch current-session files. | Add guard and IJ-013 test. |
| 2026-05-01T05:07:00+02:00 | Executor completed focused patch | `lib/features/groups/application/accept_pending_group_invite_use_case.dart`; `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Added accept-time local identity check for copied pending invites and focused IJ-013 regression; `dart format` ran on touched files. | Patch is current-session scoped. | Run focused IJ-013 tests. |
| 2026-05-01T05:07:40+02:00 | Focused IJ-013 test passed | same | `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ013'` passed (`+1`). | Row-owned accept replay seam is green. | Run adjacent identity/pending invite tests. |
| 2026-05-01T05:08:30+02:00 | Adjacent identity tests passed | receive/store/listener invite tests | `handle_incoming_group_invite_use_case_test.dart --plain-name 'recipient peer'` passed (`+3`); `store_pending_group_invite_use_case_test.dart --plain-name 'local peer identity'` passed (`+1`); `group_invite_listener_test.dart --plain-name 'copied signed invite'` passed (`+1`). | Direct, pending-store, and listener identity seams remain green. | Run invite wildcard and preservation gates. |
| 2026-05-01T05:09:40+02:00 | Invite preservation passed | invite application wildcard plus integration anchors | `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+101`); `invite_round_trip_test.dart` passed (`+14`); `group_new_member_onboarding_test.dart` passed (`+6`). | Invite and onboarding preservation is green. | Run groups gate and diff hygiene. |
| 2026-05-01T05:10:40+02:00 | Groups gate and hygiene passed | groups gate; env check; diff hygiene | `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed; `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were empty. | IJ-013 execution accepted; real-network nightly is supporting-only/unconfigured. | Run closure doc updates. |

## execution and closure evidence

Final execution verdict: accepted.

The source matrix IJ-013 row, `test-inventory.md` IJ-013 row, and this breakdown now record IJ-013 as `Covered`/accepted. The landed implementation is limited to accept-time copied pending-invite rejection for the current shipped Peer ID / `allowedDevices` invite binding contract, with no claim of a separate account/device registry or live relay/device proof.

## real scope

Close IJ-013 for the shipped trusted-private invite contract by making copied or replayed pending invites fail at accept time when the current local identity does not match the invite recipient binding.

The intended production change is narrow: `acceptPendingGroupInvite` already receives the local identity as `senderPeerId`; before materializing group/key/join state, it must compare that current identity with `GroupInvitePayload.recipientPeerId` and `GroupInvitePolicy.allowedDevices`.

## closure bar

IJ-013 can move from `Partial` to `Covered` only if the source matrix, inventory, and breakdown cite concrete evidence that:

- direct/receive handling rejects wrong-recipient invites before group/key/join state
- pending/mailbox/sync replay accept rejects copied wrong-recipient pending invites before group/key/join/consumption/message side effects
- the current shipped device binding unit is explicit: local libp2p Peer ID / `allowedDevices`, not a separate account/device registry

## source of truth

- Primary row: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` IJ-013.
- Current coverage note: `test-inventory.md` IJ-013.
- Session scope: ordered session row 12 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Production owner files: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, with preservation of `handle_incoming_group_invite_use_case.dart` and `group_invite_payload.dart`.
- Tests win over older broad prose when they reflect the current signed/encrypted invite contract.

## session classification

`implementation-ready`.

The row is evidence-gated in the breakdown, but repo inspection found a row-owned accept-time implementation gap for persisted pending invites.

## Device/Relay Proof Profile

Profile: `host-only` for required closure, with supporting `single-device`/real-network gates when configured.

Live availability checks for this run:

- `flutter devices --machine` shows `emulator-5554`, physical iPhone `00008030-001A6D2801BB802E`, and booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`.
- `xcrun simctl list devices available` confirms the same booted default iOS simulator set.
- `adb devices` is unavailable in this shell (`adb: command not found`), though Flutter lists `emulator-5554`.

Required closure evidence is the host fake-repository/app-layer invite proof because the missing accept-time replay guard is not a device-lab-only behavior. `group-real-network-nightly` remains supporting only unless the row-specific command is configured with `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES`.

## exact problem statement

Existing receive/store/listener paths reject wrong-recipient or copied invites with no pending/group/key/join side effects. A pending invite already present in the repository can still reach `acceptPendingGroupInvite`; without an accept-time local identity check, a copied pending row can be materialized on the wrong local identity if the payload is internally valid and signed.

## files and repos to inspect next

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/store_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`

## existing tests covering this area

- `handle_incoming_group_invite_use_case_test.dart` already proves bound invites accept when local identity matches and v1/v2 copied invites reject when local identity differs.
- `store_pending_group_invite_use_case_test.dart` already proves missing/mismatched local identity does not store pending invites.
- `group_invite_listener_test.dart` already proves copied signed invites do not enter pending state from the listener.
- `send_group_invite_use_case_test.dart` proves encrypted invite payloads bind `recipientPeerId` and `allowedDevices`.
- `accept_pending_group_invite_use_case_test.dart` covers many invalid persisted invite cases but does not yet prove copied wrong-recipient pending rows fail at accept time.

## regression/tests to add first

Add a focused IJ-013 accept-pending test that saves a signed pending invite for the intended receiver, then attempts accept with a different current local identity. It must assert:

- result is `invalidPayload`
- the pending row is removed
- no consumed invite tombstone is written
- no group, key, message, or `group:join` side effect exists

## step-by-step implementation plan

1. Add an accept-time recipient/device binding check in `acceptPendingGroupInvite` after payload parsing/policy validation and before revocation reuse, signature auth, materialization, or key persistence.
2. Use the existing `senderPeerId` parameter as the current local identity input because the UI call sites already load identity and pass it into acceptance.
3. When `senderPeerId` is non-empty and it does not match `payload.recipientPeerId` or is not in `payload.invitePolicy.allowedDevices`, delete the pending invite and return `invalidPayload`.
4. Add the focused IJ-013 regression in `accept_pending_group_invite_use_case_test.dart`.
5. Run focused IJ-013 tests, invite application wildcard, invite round trip, onboarding, groups gate, and `git diff --check`.
6. If all pass, update the source matrix, inventory, plan evidence, and breakdown ledger to `Covered`/accepted.

## risks and edge cases

- Many existing tests call `acceptPendingGroupInvite` without `senderPeerId`; the new guard should only enforce when a current local identity is supplied so legacy unit tests remain valid.
- UI call sites already pass `identity?.peerId` as `senderPeerId`; production accept paths therefore get the guard when identity exists.
- Wrong-recipient pending rows should be deleted rather than left as repairable because they are copied credentials, not missing key material.
- Do not broaden this session into a first-class account/device registry or sibling-device approval model.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ013'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'recipient peer'`
- `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart --plain-name 'local peer identity'`
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart --plain-name 'copied signed invite'`
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- `./scripts/run_test_gates.sh groups`
- `git diff --check`
- Supporting only when configured: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`

## known-failure interpretation

If `group-real-network-nightly` is unconfigured because `FLUTTER_DEVICE_ID` or `MKNOON_RELAY_ADDRESSES` is unset, record it as supporting-only for IJ-013. Do not classify unrelated broad-suite failures as IJ-013 regressions unless they affect invite recipient/device binding or pending accept side effects.

## done criteria

- Focused IJ-013 accept-pending regression passes.
- Existing receive/store/listener wrong-recipient identity tests remain green.
- Invite wildcard and row-adjacent integration gates pass.
- Source matrix IJ-013 row is `Covered`.
- `test-inventory.md` IJ-013 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, and ordered session row record IJ-013 as accepted/Covered.
- Residual notes do not claim a first-class account/device registry, sibling-device approval, or live device proof.

## scope guard

Do not implement account-level identity, per-device key packages, sibling-device approval, link-invite token claim, relay fixture orchestration, or UI redesign in IJ-013.

## accepted differences / intentionally out of scope

The current group invite contract binds to a local libp2p Peer ID and `allowedDevices`. This is the shipped identity/device unit for trusted-private invites. A richer account/device registry remains separate from IJ-013 and should not block this row's current app-layer wrong-recipient closure.

## dependency impact

Closing IJ-013 lets later invite/join sessions rely on copied or wrong-recipient pending invites failing before group/key/join state. IJ-014 remains responsible for welcome/key repair states, and EK/RP rows remain responsible for broader signatures, key semantics, and authorization conflict handling.
