# GE-024 Session Plan: Quoted Replies Across Membership Boundary

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GE-024`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 07:20 CEST | Controller | Source matrix GE-024 row; breakdown session ledger row 225; existing quote UI tests; existing group messaging/membership/resume tests; `ge024` runner/harness/criteria absence; current relay-backed three-device proof requirements | The source row was still `Open` while the breakdown classified the row as `needs_repo_evidence`/`evidence-gated`. Existing quote rendering covered local available and missing parents, but there was no exact remove/readd membership-boundary proof, no `quotedMessageId` assertion in the real device harness, no `ge024` criteria/runner path, and no relay-backed evidence for available and unavailable quote parents after Charlie's removal/readd window. | Reclassify GE-024 as `needs_code_and_tests`, add the exact host and widget regressions, add `ge024` runner/harness/criteria support with quoted-message-id proof capture, then rerun focused, adjacent, analyzer, and required relay-backed device proof gates. |

## Scope

GE-024 owns quoted replies in a private group while Charlie is removed and later re-added. The row closes when quote rendering follows history entitlement: a reply that quotes a parent Charlie is entitled to can resolve the parent, and a reply that quotes a parent sent during Charlie's removed window renders safely as unavailable without crashing or leaking removed-window plaintext.

Out of scope: media attachment entitlement, large-group flaky-peer behavior, first-class quote preview redesign, unrelated group UI styling, and later GO rows.

## Execution Contract

1. Add an exact host test named `GE-024 quoted replies across membership boundary preserve entitlement fallback`.
2. Send a parent before Charlie removal and another parent during Charlie's removed window.
3. Re-add Charlie, then send quoted replies to both parents.
4. Prove available quote parents remain resolvable for entitled history.
5. Prove unavailable quote parents preserve `quotedMessageId`, render safe fallback UI, and never leak removed-window parent plaintext to Charlie.
6. Add `ge024` support to the multi-party device harness, runner, and criteria validator.
7. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Device/Relay Proof Profile

Profile: `three-party/device-lab`.

Required closure evidence uses the configured group real-network relay addresses:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge024 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The three configured iOS targets represent Alice, Bob, and Charlie. Alice sends available and removed-window quote parents; Bob sends replies quoting both parents after Charlie is re-added; Charlie proves the available parent can be resolved and the unavailable parent stays a safe missing-parent fallback.

## Required Gates

| Gate | Command |
|---|---|
| Format | `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/presentation/group_conversation_screen_test.dart` |
| Focused GE-024 host proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-024 quoted replies across membership boundary preserve entitlement fallback'` |
| Focused GE-024 widget proof | `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GE-024 renders available and unavailable quote parents without crashing'` |
| Full criteria proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Scoped analyzer | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/presentation/group_conversation_screen_test.dart` |
| Adjacent group integration proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Required relay-backed three-party proof | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge024 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GE-024 scope is limited to the row-owned quoted-reply host proof, quote fallback widget proof, `ge024` multi-party criteria/runner/harness support, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented row-owned host coverage in `test/features/groups/integration/group_messaging_smoke_test.dart::GE-024 quoted replies across membership boundary preserve entitlement fallback`. The test sends a before-removal parent while Charlie is entitled, sends a removed-window parent while Charlie is removed, re-adds Charlie, then has Bob send replies quoting both parents. It proves quoted-message IDs propagate, Charlie can resolve the available parent, Charlie does not receive or persist the removed-window parent, and the unavailable quote path stays a safe fallback.

Implemented row-owned widget coverage in `test/features/groups/presentation/group_conversation_screen_test.dart::GE-024 renders available and unavailable quote parents without crashing`. The widget test renders one reply with an available parent and one reply with a missing parent, proving both surfaces render without crashing while the missing parent uses the unavailable fallback.

Added required relay-backed `ge024` support in:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

The device scenario records sent and received `quotedMessageId` values, proves Bob sends replies quoting both the available and unavailable parents, proves Alice and Charlie receive both replies with the expected quote IDs, proves Charlie has the available parent, proves Charlie lacks the removed-window parent and plaintext, proves final membership includes Charlie, and records `noCrashRenderingUnavailableQuote`.

## Verification

| Gate | Result |
|---|---|
| Dart format on GE-024 owner files | Passed. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-024 quoted replies across membership boundary preserve entitlement fallback'` | Passed: `+1 All tests passed!`. |
| `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GE-024 renders available and unavailable quote parents without crashing'` | Passed: `+1 All tests passed!`. |
| `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | Passed: `+197 All tests passed!`. |
| Scoped analyzer on GE-024 owner files | Passed: `No issues found!`. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+136 All tests passed!`. |
| Required relay-backed `ge024` proof | Passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge024_vdTEXj`, run id `1778735185620`, Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and final result `ge024 proof passed: ge024 verdicts valid for alice, bob, charlie`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GE-024 is covered by exact host quoted-reply entitlement evidence, exact widget unavailable-parent fallback evidence, and required relay-backed three-party `ge024` proof. Residual-only none for GE-024. No final program verdict is written because unresolved rows remain.
