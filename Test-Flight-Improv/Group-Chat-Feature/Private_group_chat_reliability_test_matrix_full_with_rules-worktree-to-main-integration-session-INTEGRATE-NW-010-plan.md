# INTEGRATE-NW-010 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-010`

Source row: `NW-010 | Mobile background pause and foreground resume preserve group delivery | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-010-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing, reconciling, and verifying the already-accepted NW-010 row delta into the main checkout.

## Current-Main Classification

NW-010 was partially present in main through adjacent lifecycle, replay, and fake-network recovery behavior, but exact row-owned NW-010 selectors, criteria validation, runner registration, and live-harness support were missing.

The missing meaningful row-owned test and harness delta was imported. Recovery then proved the live blocker was repo-owned in the membership-removal store-recipient path: Bob was not included in durable `member_removed` replay recipients, so Bob could retrieve the two background content replay envelopes but not the membership system envelope. A narrow production fix now stores admin removal replay for the removed member plus remaining non-self members, the NW-010 harness records the Bob recipient proof, and fresh iOS 26.2 live proof `1779235764233` accepts the row.

## Import Scope

Allowed row-owned imports:

- direct drain ordering selector in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- lifecycle resume/rejoin/drain/ack selector in `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- fake-network background/resume selector in `test/features/groups/integration/group_resume_recovery_test.dart`
- narrow production removal replay recipient repair in `lib/features/groups/presentation/screens/group_info_wired.dart`
- focused EK004 production test update in `test/features/groups/presentation/group_info_wired_test.dart`
- `private_background_resume_group_delivery` runner and live-harness support in `integration_test/scripts/run_group_multi_party_device_real.dart` and `integration_test/group_multi_party_device_real_harness.dart`
- strict `nw010BackgroundResumeDeliveryProof` criteria validation and criteria tests in `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart`
- one `test-inventory.md` entry and this integration contract

Not imported: source docs, COMPLETE_1 docs, OB-011 telemetry proof, NW-011+ rows, broader relay/shared-state work, notification repair, media work, Android work, physical iOS work, or unrelated worktree changes.

## Device/Relay Proof Profile

NW-010 requires the row-specific live app-peer proof. This integration pass used only the required iOS 26.2 CoreSimulator devices:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Relay env:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Live command rerun:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario private_background_resume_group_delivery \
  -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Preflight found no stale proof runner processes, no ambient `MKNOON_` env, and Alice/Bob/Charlie/Dana iOS 26.2 simulators booted and available before the live proof path.

## Verification

Focused host checks passed:

```sh
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'EK004 remove member broadcast stores signed member_removed replay envelope'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-010'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-010'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-010'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-010'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'replayed member_removed routes|replayed member_removed lets'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'blocks admin-only group actions until replayed membership removal settles'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios
```

Results:

- production removal replay recipient selector: PASS (`+1`)
- direct drain selector: PASS (`+1`)
- lifecycle selector: PASS (`+1`)
- fake-network selector: PASS (`+1`)
- criteria selectors: PASS (`+5`)
- membership replay preservation selectors: PASS (`+2`, `+1`, `+1`)
- runner discovery includes `private_background_resume_group_delivery`
- scoped analyzer over the touched NW-010 files: PASS (`No issues found!`)
- Dart format applied/passed
- `git diff --check`: PASS

Live proof attempts:

- Run `1779233091696`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_DkKyMg`, failed because Charlie's removed final epoch was rejected by criteria shape and Bob's verdict lacked membership-removal convergence.
- Run `1779233760981`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_9E2GM0`, failed after the criteria/harness evidence-shape correction with the narrower Bob blocker.
- Run `1779235186050`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_n3gQJF`, failed with the same Bob shape because the first recovery patch added Bob to an unrelated harness removal call; it remains diagnostic-only evidence for the store-recipient classification.
- Run `1779235764233`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_srfZDU`, passed after the production recipient fix and corrected NW-010 harness removal call.

Final live verdict for run `1779235764233`:

```text
private_background_resume_group_delivery proof passed: private_background_resume_group_delivery verdicts valid for alice, bob, charlie
```

Artifact evidence:

- `gmp_1779235764233_private_background_resume_group_delivery_orchestrator_verdict.json` records `ok=true` with Alice/Bob/Charlie role verdict paths and devices Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- `gmp_1779235764233_alice_sent_memberRemovedCharlie.json` records `inboxStored=true` and `recipientPeerIds` containing removed Charlie plus Bob, proving Bob was included in the membership replay store request.
- Bob's `orderedDrainKeys` are `aliceDuringBackgroundBeforeEdit`, `memberRemovedCharlie`, and `aliceDuringBackgroundAfterEdit`; `orderedDrainIncludesContentAndMembership=true`.
- Bob's `memberPeerIds` and `activeMemberPeerIds` contain only Alice and Bob; `finalMembershipConvergedForAliceBob=true` and `finalKeyEpochConvergedForAliceBob=true`.
- Bob proved no live background copy, replay drain completion, recovery ack after rejoin/drain, post-foreground live delivery, publish-back, topic rejoin after foreground, and duplicate visible message count `0`.

## Resolved Blocker

Resolved blocker class: `repo_owned_store_recipient_path`

The practical first check proved Bob was not a durable recipient for the membership replay envelope before the fix. The failure was not accepted as relay retrieve, drain filtering, listener apply rejection, or stale config overwrite after the recipient repair: final run `1779235764233` proves relay retrieve/drain/listener/application convergence by Bob receiving and applying `memberRemovedCharlie` between the two background content messages.

Affected rows:

- direct: `INTEGRATE-NW-010`
- no unresolved NW-010 blocker remains; `INTEGRATE-NW-011`, `INTEGRATE-NW-012`, and `INTEGRATE-NW-014` still require their own row-scoped validation before execution.

Next safe action:

- Resume at `INTEGRATE-NW-011` only when instructed. The current user instruction explicitly stops the pipeline after NW-010.
