# Sender background task fixes

Both issues from `background-task-audit.md` are now fixed locally.

## Early delivery receipt

A valid receipt can now complete an outgoing `sending` row when the exact
nonempty envelope is already staged. The database still requires the expected
peer and envelope; the receipt handler retains mutation-event and linked-device
generation checks. Unstaged or foreign receipts cannot complete the row. Later
native or relay results cannot downgrade the delivered state or restore its
ordinary retry envelope. Independent immutable relay custody is preserved.

The production change is in
`lib/core/database/helpers/messages_db_helpers.dart`. Matching test fixtures and
contract comments are synchronized. The normal integration regression is
`test/features/conversation/application/early_delivery_receipt_test.dart`, now
registered in both 1:1 test gates.

Pre-fix evidence remains in `early-receipt-counterexample.log`. That isolated
artifact used the old test fixture and is historical evidence, not the current
acceptance suite. The promoted regression covers lost native acknowledgement,
no subsequent ordinary retry, independent custody preservation, native
acknowledgement, late receipt, and foreign-peer receipt controls.

## Obsolete diagnostic transfer

The exact known legacy envelope can now be repaired even when its ordinary
parent is delivered, read, edited, hidden, deleted, or absent. Only the forbidden
outer diagnostic metadata is removed. Ciphertext, recipient, incarnation, and
retry metadata remain unchanged. A matching pending parent is repaired in the
same transaction; a terminal or newer parent stays unchanged.

The normal relay-acceptance path can then retire the repaired task. Repair alone
does not delete custody, and no arbitrary retry-age or attempt cutoff was added.
Malformed/unknown formats, ambiguous ownership, identity drift, and media,
private-message, or linked-device authority are still refused.

The production change is in
`lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart`.
Six new database-to-drain regressions failed before the change
(`obsolete-custody-red.log`). They verify restart persistence, unchanged parent
state, stale-handle fencing, and actual task completion after accepted storage.
Additional sentinels preserve private/media and ownership boundaries.

## Validation

- Flutter 3.47.2, pinned by `.fvmrc`.
- Early-receipt focused suites: 36 tests passed
  (`early-receipt-focused-green.log`).
- Initial custody helper/drain suites: 39 tests passed
  (`obsolete-custody-green.log`). Five additional preservation cases were added
  during review and are included in final validation.
- Final 1:1 gate across 220 exact test files passed: 3,712 tests passed,
  four existing tests skipped, no failures, in 3 minutes 11 seconds
  (`sender-fix-1to1-gate.log`). This includes the final five class-preservation
  cases and all synchronized fixtures.
- `git diff --check` and test-gate shell syntax checks pass.
- Changed-file impact analysis covers all 15 changed source/test/gate paths.
- Incremental architecture graph refresh completed
  (`sender-fix-graph-refresh.log`).

No deployment, installation, or release has been performed. These sender fixes
require an updated app build. The separate relay notification deduplication
patch still requires a relay deployment built with Go 1.25.0.
