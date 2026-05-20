# INTEGRATE-PL-002 Worktree-To-Main Contract

Status: accepted

Mode: standard worktree-to-main import/reconcile/verify. This is not gap-closure. Do not recreate or rewrite the historical source implementation plan; use it only as historical truth.

## Source Contract

- Source row: `PL-002` - media-only group message is allowed when text is empty.
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-002-plan.md`.
- Source status: Covered / accepted.
- Source live proof: run `1778926084242` on iOS 26.2 app-peer devices Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Source evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_pl002_IM5mNj`.
- Source live command:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl002 --device 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Current active ledger has `PL-002` pending. Current main lacks exact `PL-002` / `pl002` proof surfaces, so this is an import, not a skip.

## Import Scope

Import only missing row-owned meaningful deltas needed to make current main carry the accepted `PL-002` proof. Reconcile carefully with dirty accepted/blocked rows already present in main, especially `NW-013`, `NW-014`, `NW-015`, and `PL-001`. Preserve all existing dirty integration edits.

Future executor write scope is limited to:

- This plan file.
- `test/features/groups/application/send_group_message_use_case_test.dart`.
- `test/features/groups/integration/group_media_fanout_test.dart`.
- `go-mknoon/bridge/bridge_test.go`.
- `integration_test/group_multi_party_device_real_harness.dart`.
- `integration_test/scripts/run_group_multi_party_device_real.dart`.
- `integration_test/scripts/group_multi_party_device_criteria.dart`.
- `test/integration/group_multi_party_device_criteria_test.dart`.

No production code is allowed unless a focused `PL-002` proof proves current production rejects media-only empty text. Controller inspection says production behavior already permits media-only empty text.

## Explicit Exclusions

- `PL-003` bridge `TrimSpace` behavior or no-media rejection production changes.
- `PL-003` row-named Flutter tests.
- `PL-012+`.
- Media ACL/privacy rows `PL-005` through `PL-007`.
- Source docs, `COMPLETE_1` docs, test-inventory, ledger, and criteria/source documents until closure.
- Unrelated `NW-014` fixture repair.
- Unrelated harness/criteria proofs.

## Required Focused Checks

- `PL-002` app selector.
- `PL-002` fake-network fanout selector.
- `PL-002` criteria selector.
- Go bridge selector set with `TestPL002`, existing media-only acceptance, and `PL-003` blank/no-media guard.
- Runner scenario list/discovery for `pl002`.
- Format, `gofmt`, analyze, and diff hygiene.

## Required Preservation Checks

- `PL-001` unit selector.
- `DE-003` send selector.
- `IR-014` send selector.
- Criteria preservation around `DE-003`, `IR-015`, and `NW-014` as feasible.

## Required Post-Import Live Proof

After import, rerun `pl002` on iOS 26.2 only using the exact Alice/Bob/Charlie device ids and relay environment from the source plan:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl002 --device 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

If the current live fixture fails before verdict for a reason unrelated to `PL-002` code, classify `blocked_external_fixture` with the exact run id, devices, and log signature.

## Broad Gates

- Groups gate.
- Completeness-check gate for residual classification.

## Terminal Statuses

- `accepted`
- `skipped_already_present`
- `blocked_conflict`
- `blocked_external_fixture`

## Execution Progress

- 2026-05-20 18:12 CEST - Contract extracted from this INTEGRATE-PL-002 plan and historical source plan. Scope limited to row-owned PL-002 proof imports in the allowed files; no production code required.
- 2026-05-20 18:13 CEST - Imported PL-002 application proof, fake-network media fanout proof, Go row selector, runner scenario discovery, harness scenario dispatch, live proof fields, and criteria/unit-test support. Skipped PL-003 production behavior, PL-003 row-named Flutter tests, PL-012+, media ACL/privacy rows, source docs, ledger, and test-inventory updates.
- 2026-05-20 18:14 CEST - Initial focused fanout and live criteria checks exposed current-main proof schema differences (`mediaAttachments` / `mediaAttachmentCount` instead of source-era `media` / `mediaCount`). Reconciled only PL-002 harness and criteria proof readers to current main.
- 2026-05-20 18:15 CEST - Focused host checks passed: scoped `dart format --set-exit-if-changed`; `cd go-mknoon && go test ./bridge -run 'TestPL002|TestGroupPublish_MediaOnly_AcceptsEmptyText|TestPL003GroupPublishEmptyTextAndNoMediaFailsInvalidInput' -count=1`; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-002"`; `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-002"`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "PL-002"`; `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl002 --list-scenarios`; scoped `flutter analyze --no-pub`; and scoped `git diff --check`.
- 2026-05-20 18:15 CEST - Preservation checks passed for PL-001, DE-003, IR-014, and criteria `DE-003|IR-015|NW-014` selectors.
- 2026-05-20 18:20 CEST - First live proof run `1779293749363` launched all three requested iOS 26.2 devices and delivered the media-only message, but failed orchestrator criteria because PL-002 proof validation still expected source-era media field names. Classified as repo-owned proof-schema import mismatch and fixed before final live rerun.
- 2026-05-20 18:24 CEST - Required PL-002 live proof passed with run id `1779294075668`, evidence dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_pl002_nk5AtA`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, exact relay env from contract. Orchestrator verdict: `pl002 proof passed: pl002 verdicts valid for alice, bob, charlie`.
- 2026-05-20 18:27 CEST - Controller spot-checks passed after executor return: `git diff --check` over PL-002 row files; `cd go-mknoon && go test ./bridge -run 'TestPL002|TestGroupPublish_MediaOnly_AcceptsEmptyText|TestPL003GroupPublishEmptyTextAndNoMediaFailsInvalidInput' -count=1`; PL-002 send-use-case, fake-network fanout, and criteria Flutter selectors; and `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl002 --list-scenarios`. Tooling-only `info.plist` LastAccessedDate churn from the live proof was restored and is clean.

## Final Verdict

Status: `accepted`

Current main now carries the row-owned PL-002 proof surfaces from the accepted source worktree, reconciled with current dirty NW/PL rows and current-main harness verdict schema. No production code was changed.
