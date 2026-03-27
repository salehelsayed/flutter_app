# Session 31 Plan — Resolve `reuse` transport to real connection type

## Real Scope

What changes in this session:

- stop persisting `transport: 'reuse'` for new outgoing 1:1 messages on the
  already-connected fast path
- infer the real transport label from the current connection state:
  `local`, `relay`, or `direct`
- keep UI rendering safe for pre-existing rows that still contain `reuse`
- add direct regressions that pin the reuse-fast-path transport label

What does not change in this session:

- no new `P2PService` interface method
- no changes to `P2PServiceImpl._inferTransportForPeer`
- no changes to incoming-message transport labeling
- no changes to group or announcement transport labels
- no fix for `_tryRelayProbeSend` labeling
- no DB migration for old rows already stored as `reuse`
- no Go / bridge / transport-stack changes

---

## Closure Bar

This session is sufficient when all of the following are true:

- new outgoing 1:1 messages sent through the reuse fast path persist
  `local`, `relay`, or `direct`, never `reuse`
- relay-backed reused connections show the relay icon
- local reused connections show the WiFi/local icon
- non-relay reused connections show the direct icon
- old rows that still contain `reuse` continue to render the direct icon as a
  legacy fallback
- no abstract interface or migration work is added just to fix this label

---

## Source of Truth

Authoritative sources for this session:

- this plan: `Test-Flight-Improv/session-31-plan.md`
- current code and tests in the 1:1 send path and conversation UI
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Conflict rules:

- current code and tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on named-gate
  membership
- this plan is the active execution contract unless repo evidence proves a step
  stale or wrong

---

## Session Classification

`implementation-ready`

Why:

- the bug is concrete and repo-local
- the relevant send seam already exists in one file
- the reference transport inference logic already exists in
  `p2p_service_impl.dart`
- the needed tests already exist and only require narrow extensions

---

## Exact Problem Statement

When an outgoing 1:1 message reuses an already-connected peer,
`send_chat_message_use_case.dart` currently persists `via: 'reuse'` on the
successful fast path. The UI then renders the generic direct icon for every
reused connection, even when the actual underlying path is relay or local WiFi.

This is a correctness issue in sender-visible transport labeling, not a
transport-behavior issue. The message still sends, but the persisted label and
icon can be wrong.

What must improve:

- the reuse fast path must persist the real transport label
- transport UI must reflect the actual reused connection type for new rows

What must stay unchanged:

- the fast path still short-circuits discover / dial when a connection already
  exists
- legacy rows with `reuse` stay renderable

---

## Files and Repos to Inspect Next

Production files to inspect:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/services/p2p_service_impl.dart` (reference only)
- `lib/core/services/p2p_service.dart` (confirm no interface change)
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/core/database/migrations/012_transport_column.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`

Tests to inspect:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/integration/onboarding_golden_path_test.dart`

No Go, relay, or external repo work is expected.

---

## Existing Tests Covering This Area

Already present:

- `send_chat_message_use_case_test.dart` already covers the connected-peer reuse
  fast path and proves it skips discover / dial
- `letter_card_test.dart` already covers the `reuse` icon fallback
- `onboarding_golden_path_test.dart` already pins the legacy `reuse` label in a
  broader confidence flow
- the named `1to1` gate already covers adjacent send / retry / inbox /
  interruption behavior that should not regress

Still missing:

- direct proof that reused relay connections persist `relay`
- direct proof that reused local connections persist `local`
- direct proof that reused direct connections persist `direct`
- plan-level clarity that `reuse` remains legacy-only in the UI / docs

---

## Regression / Tests to Add First

Add these direct proofs before implementation:

1. `send_chat_message_use_case_test.dart`
   - reuse path + `/p2p-circuit` multiaddr => persisted `relay`
   - reuse path + non-relay multiaddr => persisted `direct`
   - reuse path + local peer => persisted `local`
2. `letter_card_test.dart`
   - keep the existing `reuse` icon test, but mark it as a legacy-row fallback
3. `onboarding_golden_path_test.dart`
   - update the broad matcher so it accepts the real new labels and stops
     expecting `reuse`

These are the minimum regressions needed to prove the exact seam being changed
without widening scope.

---

## Step-by-Step Implementation Plan

1. Confirm the current reuse fast path in
   `send_chat_message_use_case.dart` persists `via: 'reuse'` and that the fast
   path still must skip discover / dial.
2. Add a small helper in `send_chat_message_use_case.dart` that infers the
   transport for an already-connected peer from `p2pService.currentState` and
   `p2pService.isLocalPeer(peerId)`.
3. Use local-first precedence:
   - if `isLocalPeer(peerId)` => `local`
   - else if any matching connection multiaddr contains `/p2p-circuit` =>
     `relay`
   - else => `direct`
4. Replace the reuse fast-path `via: 'reuse'` callsite with the helper result.
5. Keep `case 'reuse'` in `letter_card.dart` as a legacy fallback with an
   explicit comment.
6. Update the transport comments in:
   - `conversation_message.dart`
   - `012_transport_column.dart`
   so `reuse` is clearly documented as legacy-only for old rows.
7. Add / update the direct tests above.
8. Stop after the transport-label seam is fixed. Do not broaden into relay
   probe labeling or transport API cleanup.

If repo evidence shows the helper cannot determine the real transport from the
current connection state alone, stop and reopen the plan as evidence-gated
instead of inventing a wider architecture.

---

## Risks and Edge Cases

- empty multiaddrs on an already-connected peer fall back to `direct`; this is
  acceptable because the current UI already treats `reuse` as the generic
  direct-like fallback
- multiple connections for the same peer should return `relay` if any matching
  connection carries `/p2p-circuit`
- `isLocalPeer(peerId)` must win over multiaddr inspection so local reuse keeps
  the WiFi/local icon
- old DB rows with `reuse` must continue to render safely
- this session should not accidentally change the send ordering or inbox-fallback
  behavior of the reuse path

---

## Exact Tests and Gates to Run

Direct suites:

- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/integration/onboarding_golden_path_test.dart`

Named gates:

- `./scripts/run_test_gates.sh 1to1`
  - required because this session changes a shared 1:1 send-path label
- `./scripts/run_test_gates.sh baseline`
  - required because Flutter production files change

Not required by default:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh feed`
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`

Reason:

- the change is 1:1-only
- it does not touch feed entry, group messaging, or lifecycle / transport
  recovery wiring

`flutter test` for the full repo is not required by the regression strategy and
should not replace the direct suites plus named gates above.

---

## Known-Failure Interpretation

- use `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  known failures and gate scope
- the `1to1` gate is currently documented as green; any new failure there is a
  blocker unless clearly shown to be unrelated and pre-existing
- `onboarding_golden_path_test.dart` is an optional/manual direct suite in the
  gate definitions, but it is required for this session because it currently
  encodes the stale `reuse` expectation
- unrelated red tests outside the direct suites and required named gates are
  not Session 31 regressions unless this change clearly caused or widened them

---

## Done Criteria

- `send_chat_message_use_case.dart` no longer persists `via: 'reuse'` for new
  outgoing 1:1 messages
- direct tests prove relay / direct / local resolution on the reuse fast path
- `letter_card.dart` still renders legacy `reuse` rows safely
- `conversation_message.dart` and `012_transport_column.dart` document `reuse`
  as legacy-only
- required direct suites are green
- `./scripts/run_test_gates.sh 1to1` and
  `./scripts/run_test_gates.sh baseline` are green
- no interface, migration, group, or transport-stack scope drift occurred

---

## Scope Guard

- do NOT add a new `P2PService` interface method
- do NOT move `_inferTransportForPeer` out of `P2PServiceImpl`
- do NOT fix `_tryRelayProbeSend` labeling here
- do NOT migrate old DB rows with `transport: 'reuse'`
- do NOT change group or announcement transport labeling
- do NOT touch DI, Go, bridge, relay-server, or transport orchestration

---

## Accepted Differences / Intentionally Out of Scope

- old rows may still contain `reuse`; the UI fallback remains intentionally
  supported
- relay-probe labeling remains a separate issue
- this session improves sender-visible label accuracy, not transport selection or
  delivery guarantees

---

## Dependency Impact

- any later cleanup that removes the legacy `reuse` UI fallback should only
  happen after enough old rows have naturally aged out or after a separate
  migration decision
- any future relay-probe label cleanup should build on this same transport
  vocabulary (`local`, `direct`, `relay`, `inbox`) rather than reintroducing a
  new label
- this session should land before broader transport-icon cleanup work so future
  UI audits do not keep treating the reuse fast path as an accepted mismatch
