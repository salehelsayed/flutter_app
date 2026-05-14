# GE-023 Session Plan: Media Attachments Through Remove/Readd

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GE-023`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 06:45 CEST | Controller | Source matrix GE-023 row; breakdown session ledger row 224; existing group messaging/membership/resume tests; existing media attachment forwarding behavior; `ge023` criteria/runner/harness absence; current relay-backed three-device proof requirements | The source row was still `Open` while the breakdown classified the row as `needs_repo_evidence`/`evidence-gated`. Existing code forwarded live media metadata but there was no exact remove/readd entitlement proof, no SQL-backed media attachment repository wiring in the device harness, no `ge023` criteria/runner path, and no durable replay proof that media metadata survived encrypted `group:inboxStore` custody. | Reclassify GE-023 as `needs_code_and_tests`, add the exact host media entitlement regression, wire SQL-backed media attachment persistence into the real harness listener stack, add `ge023` runner/harness/criteria support, decode recorded replay envelopes for durable media proof, then rerun focused, adjacent, analyzer, and required relay-backed device proof gates. |

## Scope

GE-023 owns media attachment entitlement in a private group while Charlie is removed and later re-added. The row closes when entitled members receive media metadata/content for messages sent before removal, during Charlie's removed window, and after re-add, while Charlie cannot receive or persist removed-window media.

Out of scope: quoted replies, large-group flaky-peer behavior, media upload/download transport storage outside the message attachment metadata contract, unrelated group UI rendering polish, and later GE-024+ rows.

## Execution Contract

1. Add an exact host test named `GE-023 media attachments in private group through remove/re-add respect entitlement`.
2. Send encrypted image media before Charlie removal, during Charlie's removed window, and after Charlie is re-added.
3. Prove Alice, Bob, and Charlie receive entitled media metadata/content according to membership windows.
4. Prove Charlie does not receive or persist removed-window message plaintext or attachment rows.
5. Add `ge023` support to the multi-party device harness, runner, and criteria validator.
6. Wire SQL-backed `MediaAttachmentRepositoryImpl` into the real harness listener stack and durable inbox drain path.
7. Prove durable replay payload media by decoding recorded `group:inboxStore` envelopes through production `decodeInboxMessage`.
8. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Device/Relay Proof Profile

Profile: `three-party/device-lab`.

Required closure evidence uses the configured group real-network relay addresses:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge023 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The three configured iOS targets represent Alice, Bob, and Charlie. Alice sends media before removal and during Charlie's removed window; Charlie sends media after re-add.

## Required Gates

| Gate | Command |
|---|---|
| Format | `dart format test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Focused GE-023 host proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-023 media attachments in private group through remove/re-add respect entitlement'` |
| Full criteria proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Scoped analyzer | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` |
| Adjacent group integration proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Required relay-backed three-party proof | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge023 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GE-023 scope is limited to the row-owned media host proof, `ge023` multi-party criteria/runner/harness support, SQL-backed media repository harness wiring, durable media replay proof capture, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented row-owned host coverage in `test/features/groups/integration/group_messaging_smoke_test.dart::GE-023 media attachments in private group through remove/re-add respect entitlement`. The test sends encrypted image media before removal, during Charlie's removed window, and after re-add. It proves Alice/Bob/Charlie receive before-removal media, Alice/Bob receive removed-window media, Charlie does not receive or persist the removed-window message or attachment, all entitled members receive post-readd media, attachment metadata includes content hash and encryption metadata, and sender rows keep local `done` media state.

Added required relay-backed `ge023` support in:

- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

The device scenario runs Alice, Bob, and Charlie through before-removal, removed-window, and post-readd media sends. It validates sent recipient windows, live media payloads, SQL-backed persisted attachment rows, encrypted durable replay payload media, final membership, and Charlie's removed-window exclusion. The real harness now constructs `MediaAttachmentRepositoryImpl` from SQL helpers and supplies it to `GroupMessageListener` and offline inbox drain paths.

## Same-Session Recovery

The first required relay-backed `ge023` proof failed because sent verdicts reported `durableMediaCount == 0`. The failure was repo-owned harness evidence capture, not product behavior: the proof inspected the encrypted replay envelope instead of the signed message plaintext stored inside it. The harness now decodes recorded `group:inboxStore` replay payloads through production `decodeInboxMessage` before counting durable media. The rerun passed the exact required relay proof.

## Verification

| Gate | Result |
|---|---|
| Dart format on GE-023 owner files | Passed. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-023 media attachments in private group through remove/re-add respect entitlement'` | Passed: `+1 All tests passed!`. |
| `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | Passed: `+195 All tests passed!`. |
| Scoped analyzer on GE-023 owner files | Passed: `No issues found!`. |
| `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` | Passed: `+135 All tests passed!`. |
| Required relay-backed `ge023` proof | Passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge023_7Y5Mx0`, run id `1778733356540`, Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and final result `ge023 proof passed: ge023 verdicts valid for alice, bob, charlie`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GE-023 is covered by exact host media entitlement evidence plus required relay-backed three-party `ge023` proof. Residual-only none for GE-023. No final program verdict is written because unresolved rows remain.
