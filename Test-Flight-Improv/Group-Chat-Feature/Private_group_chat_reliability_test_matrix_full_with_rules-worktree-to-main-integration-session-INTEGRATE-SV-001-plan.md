# INTEGRATE-SV-001 Minimal Integration Contract

Status: accepted

## Row Scope

- Source row: `SV-001` - Never-member cannot publish to private group.
- Mode: standard worktree-to-main integration; this is import/reconcile/verify work, not gap-closure replanning.
- Historical source-of-truth: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-001-plan.md`.
- Main reconciliation: partially present. COMPLETE_1/current main already covered raw non-member validation through GA-002 and safe validator diagnostics through GA-026, but local publish/reaction errors still exposed full identifiers and the SV-001 listener, fake-network, criteria, runner, and live proof artifacts were missing.

## Integrated Delta

Imported only the missing row-owned SV-001 surfaces:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

No source-worktree docs, source matrix rows, COMPLETE_1 docs, adjacent SV rows, notification/media/share rows, Android, physical iOS, or unrelated fixture repairs were imported.

## Verification

- `cd go-mknoon && go test ./node -run 'TestSV001|TestGA002NonMemberCannotPublishValidEnvelope|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons' -count=1` passed.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_never_member_publish_rejected --list-scenarios` listed `private_never_member_publish_rejected`.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "SV-001"` passed.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "SV-001"` passed.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "SV-001"` passed (`+4`).
- `cd go-mknoon && go test ./node -run 'TestSV001NeverMemberRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestRP017RemovedPeerContinuedPublishesAreRejectedBeforeAcceptAndForward' -count=1` passed.
- `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with `No issues found!`.
- `gofmt` and `dart format --set-exit-if-changed` passed on row-owned files.
- Scoped `git diff --check` passed on row-owned files before doc closure.

## iOS 26.2 Proof

Required live proof passed on iOS 26.2 simulators only:

- Scenario: `private_never_member_publish_rejected`
- Run id: `1779333243408`
- Evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_z2Oq7f`
- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana: `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Orchestrator verdict: `private_never_member_publish_rejected proof passed: private_never_member_publish_rejected verdicts valid for alice, bob, charlie, dana`

## Closure Verdict

Accepted. SV-001 is integrated in main with row-owned code, tests, criteria, runner, and iOS 26.2 live evidence. Existing blockers remain unrelated: `KE-007` and `KE-009` are `blocked_conflict`; `ML-012`, `NW-014`, `UP-002`, `UP-004`, `UP-006`, `UP-009`, `UP-010`, and `UP-011` are `blocked_external_fixture`. Next safe row is `INTEGRATE-SV-002` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation.
