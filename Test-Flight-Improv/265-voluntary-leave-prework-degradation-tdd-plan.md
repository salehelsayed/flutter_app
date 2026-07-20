# 265 - Voluntary-Leave Prework Must Degrade, Not Abort (Hardening)

Status: planned (v1 authored 2026-07-20; awaiting $tdd-review audit; NOT executed)
Type: hardening
Closure tier: unit proof (fake bridge / fault-injected repos); no device journey needed
Boundary triggers: Flutter-only (voluntary-leave prework use case); no relay, bridge,
native-handler, or wire-format production change
Spec: free-text intent — 2026-07-20 session: leaving a group must succeed whenever the
user's intent is unambiguous; secondary best-effort legs (offline replay envelopes,
key rotation) must not veto the exit. "I want the group administration to be reliable."
Grounding: throw-path census of the prework verified at HEAD ad073dd39 (anchors below).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | broadcast_voluntary_leave_use_case.dart, leave_group_and_delete_local_history_use_case.dart, bridge_group_helpers.dart (callGroupPublish/callGroupLeave) | Throw census complete; per-leg tolerance policy drafted | Run $tdd-review 265, execute RED-first |

## Source Of Truth
- Spec / intent: inline above
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
planning-only (no implementation in this session)

## Exact Problem Statement
The voluntary-leave prework (`broadcastVoluntaryLeaveAndRotateKey`) is called inside a
try/catch whose ANY exception becomes `preworkFailed` → "Failed to leave group"
(leave_group_and_delete_local_history_use_case.dart:252-269). Two of its legs already
degrade correctly; two can still abort the whole leave even though the user's exit
intent does not depend on them.

## Verified Leg Census (broadcast_voluntary_leave_use_case.dart, HEAD ad073dd39)
Degrades correctly today:
- Live publish :149-162 — `callGroupPublish` NEVER throws on command failure; it
  returns the error map (bridge_group_helpers.dart:388-414, TimeoutException →
  `BRIDGE_TIMEOUT` map). Offline leave works because of this.
- Key rotation :196-225 — explicitly best-effort; a null rotation is recorded as
  `rotationDeferred` (:216) and a remaining admin re-keys on receipt.
Can abort the leave today:
- A. Signed transition payload :112-133 (`signGroupSystemTransitionPayload`) — a
  bridge/crypto failure throws, aborting the exit.
- B. Offline replay envelope :177-191 (`storeGroupOfflineReplayEnvelope` with
  `recipientPeerIds`) — a failure for ANY recipient (e.g. missing key material for one
  member) throws, aborting the exit for everyone.
- C. Timeline message save :144-147 (`msgRepo.saveMessage`) — a DB error aborts
  (acceptable: local DB broken means cleanup would fail too; out of scope).

## Fix Outline (execution session implements)
1. Leg B per-recipient tolerance: envelope storage becomes best-effort per recipient —
   skip recipients whose envelope cannot be prepared, record which were skipped in the
   `VoluntaryLeaveBroadcastResult` (new field), continue the leave. Remaining members
   still learn of the departure via the live publish and/or admin-side pruning on
   `member_removed` receipt (group_message_listener.dart:3621-3664 re-key path).
2. Leg A classification: a signing failure is terminal for the SIGNED broadcast but not
   necessarily for the exit. Policy decision to fix in execution (default proposal):
   one retry, then fail the leave with a cause-coded error (this remains a real
   failure; unsigned member_removed must never be published). Rationale: unlike leg B
   this is all-or-nothing — no partial degradation exists that preserves the signed
   transition contract.
3. Thread the skip information through
   `LeaveGroupAndDeleteLocalHistoryResult.broadcastResult` so callers/diagnostics can
   distinguish a clean broadcast from a degraded one (pairs with plan 266 surfacing).

## RED-First Test Plan
- Fault-injected envelope store: failure for one of three recipients → leave still
  completes (`left`), result records the skipped recipient; failure for all
  recipients → leave still completes, all recorded.
- Signing failure → exit fails with a distinct cause (not the generic prework
  StateError), and one retry was attempted.
- Preservation: publish-failure and rotation-failure behavior unchanged (existing
  offline-leave tests keep passing); rollback of tentative artifacts on the paths that
  still abort remains intact (:214-269).

## Sibling Open-Sites
- The dissolve flow (dissolve_group_use_case.dart) and role-change broadcast use the
  same signing/envelope primitives — audit whether the same tolerance policy applies
  or is intentionally stricter there.

## Gates
- GROUP_TESTS: ./scripts/run_test_gates.sh groups
- AUTO_FEATURE_HOST: ./scripts/run_host_test_gates.sh feature-host-all
  --batch-flutter --concurrency 4 --reporter failures-only
- Explicit grep-gate registration for new tests; flutter analyze clean.

## Risks / Open Questions
- Ghost-membership window: a recipient skipped in leg B learns of the departure later
  (or never, if permanently offline) — quantify against the existing catch-up
  mechanisms during execution before choosing silence vs. a retry queue for skipped
  envelopes.
- Leg A retry must not double-publish if the first sign actually succeeded at the
  bridge but the response was lost (idempotency via `sourceEventId` :110-111).
