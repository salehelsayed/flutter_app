# INTEGRATE-IR-008 Inbox Retrieve Failure Cursor/Ack Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-008 - Inbox retrieve failure does not advance cursor or ack state`.
- Historical source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-008-plan.md`.
- Source closure: `closed` / `accepted`, with source matrix row marked `Covered`.
- Source selectors:
  - `IR-008 retrieve failure leaves cursor and ack state unchanged until retry`
  - `IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once`

## Integration Scope

This is a standard worktree-to-main integration contract only. It does not recreate the original implementation plan and does not reimplement IR-008 from scratch.

IR-008 owns only failed group offline inbox cursor retrieve before page application:

- failed `group:inboxRetrieveCursor` must leave the durable cursor unchanged.
- failed retrieve must not persist message rows, delivered/read receipts, or local ack state for the failed page.
- retry must request the same cursor and persist the same unread page exactly once.

Out of scope: IR-009 persistence-before-ack, history repair, relay-side ACLs, media replay breadth, UI, notifications, Android, physical iOS, iOS live proof, criteria harnesses, and adjacent replay rows.

## Reconciliation Result

Production code was skipped as already present in current main. `drain_group_offline_inbox_use_case.dart` already retrieves before page writes, commits cursor/receipts inside `runInboxPageTransaction` only after successful page processing, and returns a failed `GroupOfflineInboxDrainResult` for retrieve errors without committing page state.

Current main was missing the row-owned proof artifacts, so this integration imported only:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - added `IR-008 retrieve failure leaves cursor and ack state unchanged until retry`
  - reconciled the source fixture to current main's local-membership replay precondition inside the row-owned test only
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - added `_FailFirstCursorInboxBridge`
  - added `IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once`

No production, harness, criteria, simulator, live-proof, or fixture files were changed for IR-008.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-008 retrieve failure leaves cursor and ack state unchanged until retry' # +1
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once' # +1
flutter analyze --no-pub lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart # No issues found
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-004 live plus inbox replay duplicate|IR-003 timestamp replay boundary|temporary partition replays missed backlog|GR-015 relay reconnect' # +4
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --name 'group:inboxRetrieveCursor|group:inboxRetrieve timeout|BridgeCommandException on ok:false|transient relay EOF' # +10
git diff --check
```

The drain preservation selector bundle:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'PREREQ-GROUP-SYNC-RECEIPTS failed page commit|PREREQ-GROUP-SYNC-RECEIPTS listener replay failure|PREREQ-GROUP-SYNC-RECEIPTS system replay failure|BB-013 group:inboxRetrieve timeout|IR-002 cursor drain resumes|IR-003 timestamp high-water|GI-026 history gap metadata|DE-004 listener-backed live plus replay|GE-018 seeded offline replay envelope tampering|GO-008 cursor error flow logs'
```

returned `+9 -1`; the only failure was the pre-existing non-IR-008 `GE-018 seeded offline replay envelope tampering rejects before plaintext render` valid-control fixture (`Expected: not null / Actual: <null>`), caused by missing local membership in that selector. It is outside the IR-008 row-owned delta and was not rewritten.

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

remained red at `+211 -3`, only on preserved non-IR-008 residuals `BB-007`, `BB-012`, and `GM-029`.

```bash
./scripts/run_test_gates.sh completeness-check
```

remained red on the unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification gap (`732/733`).

## Device/Live Proof

No iOS 26.2 simulator or live proof was required. Source `3-Party E2E` is `N/A`, and IR-008 is host-only.

## Closure Verdict

`INTEGRATE-IR-008` is accepted. The missing row-owned IR-008 proof artifacts are imported into current main, current main production behavior is already present, and no adjacent row closure is claimed.
