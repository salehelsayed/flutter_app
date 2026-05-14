# GE-019 Session Plan - Property Test Random Key Rotations Preserve Access Windows

## Status

Status: accepted/closed

## Original Source Row

`GE-019 | Property test random key rotations preserve access windows | Model key epochs and membership windows. | 1. Random rotate/remove/add/send. 2. Try decrypt per peer. 3. Compare model. | Peers decrypt exactly model-authorized messages. | P0 | Open | Required | Required | N/A | Required | N/A | Finds epoch/grace bugs like PrevKeyEpoch 0.`

## Reconciliation Verdict

At planning intake, the source matrix row was still `Open`, while the session ledger marked GE-019 `needs_repo_evidence/evidence-gated` and pointed at a non-existent adjacent GE-019 plan. Baseline selector proof confirmed the exact row-owned test was missing:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-019'` exited 79 with `No tests ran. No tests match "GE-019".`

This is a repo-owned proof gap. Reclassify the session as `needs_code_and_tests` until the source row, breakdown, and inventory carry concrete file/test/gate evidence.

## Scope

Owned implementation surface:

- `test/features/groups/integration/group_messaging_smoke_test.dart`

Owned documentation surface after proof passes:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- this plan file

Out of scope:

- Production behavior changes unless the exact property proof exposes a current product defect.
- Simulator or three-device harness changes, because the source row marks Smoke and 3-Party E2E as N/A and the required proof is fake-network integration.

## Execution Contract

Add `GE-019 seeded random key rotations preserve access windows` to `group_messaging_smoke_test.dart`.

The test must:

- run multiple deterministic seeds over random rotate/remove/add/send operations;
- keep a model of active membership, send-time recipient authorization, and current key epoch;
- assert every sender persists exactly one outgoing row at the modeled epoch;
- assert every active-at-send recipient persists exactly one incoming row at the modeled epoch;
- assert peers removed or not yet added at send time never render that plaintext, even after later re-add;
- assert inactive sends do not publish or mutate the local message set;
- assert active peers converge on the modeled active member set and latest key epoch after each operation;
- include enough seed/step/operation context in assertion reasons to make failures reproducible.

## Required Validation

- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart`
- `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-019'`
- `./scripts/run_test_gates.sh groups`
- `git diff --check` on the row-owned test and docs

## Acceptance Bar

GE-019 may be marked accepted only after the source matrix row is `Covered` with exact file/test/gate evidence, this plan records the final execution evidence, and the breakdown session ledger no longer treats GE-019 as evidence-gated/open. This bar is satisfied by the execution evidence and final verdict below.

## Execution Evidence

Implemented `test/features/groups/integration/group_messaging_smoke_test.dart::GE-019 seeded random key rotations preserve access windows`.

The test runs deterministic seeds `19019`, `19020`, and `19021`, 36 operations per seed, over an A/B/C/D private-group model. The operation stream includes guaranteed and random sends, key rotations, removals, re-adds, and inactive sends. The oracle records seed, step, operation, active set, current key epoch, and operation log in failure context.

The proof asserts:

- sender rows persist exactly once at the modeled epoch;
- active-at-send recipient rows persist exactly once at the modeled epoch;
- peers removed or not yet added at send time never render that plaintext, even after later re-add;
- inactive sends do not publish and do not mutate local message ids;
- active peers converge on the modeled member set and latest key epoch after every operation;
- duplicate active member/device rows do not appear.

Validation:

- Baseline selector before implementation: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-019'` exited 79 with `No tests ran. No tests match "GE-019".`
- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart` passed after formatting.
- `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-019'` passed (`+1`).
- `./scripts/run_test_gates.sh groups` passed (`+158`).

## Final Verdict

Accepted/closed. GE-019 is covered by row-owned host fake-network property proof. No production, Go, simulator, runner, or device-harness changes were required because the source row marks Smoke and 3-Party E2E as N/A and requires fake-network integration proof.
