# EC-003 Session Plan - Future event inputs do not corrupt current state

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:46:00+02:00 | Local planner completed | EC-003 source matrix row; ordered-session EC-003 row; `go-mknoon/node/pubsub_key_rotation_grace_test.go`; `handle_incoming_group_message_use_case_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_messaging_smoke_test.dart`; EK-005 and ER-004 blocker notes | Existing shipped behavior is reject/placeholder/enrich rather than durable future-key queue repair. EC-003 can close only if direct evidence proves future timestamps, live future epochs, offline future epochs, and later valid replay dependencies do not corrupt current state. Durable key-sync repair lifecycle remains EK-005/ER-004 scope. | Run focused Go and Flutter evidence, recover any stale test fixture exposed by strict sender validation, then close EC-003 with explicit scope guard. |

## Execution Progress

| timestamp | role | files inspected or updated | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:47:00+02:00 | Local executor completed | `test/features/groups/integration/group_messaging_smoke_test.dart` | Supporting live skew smoke failed because the fixture added Charlie locally but never broadcast the membership event to existing recipients before Charlie published under strict sender validation. Added the missing `broadcastMemberAdded` setup step; no production code changed. | Rerun the supporting smoke and complete focused EC-003 gates. |
| 2026-05-01T11:48:00+02:00 | Local verifier completed | Go future-epoch validator proof; Flutter timestamp clamp proof; offline future-epoch placeholder proof; live skew smoke; duplicate replay enrichment tests | All focused EC-003 gates passed after the smoke fixture recovery. Evidence proves future-dated messages clamp or order safely, live unknown future epochs reject before delivery, offline future epochs create one safe undecryptable placeholder, and later valid replay enriches sparse prior rows without duplicate/corrupt state. | Persist EC-003 as `Covered` with EK-005/ER-004 repair-lifecycle caveat. |

## real scope

EC-003 covers shipped behavior for future or dependency-delayed inputs:

- far-future timestamps are clamped to receive time, while past/current/near-future timestamps retain chronological order
- fake-network live skewed messages preserve sane ordering and latest-message state after valid membership hydration
- live PubSub messages for an unknown future key epoch are rejected before delivery
- offline encrypted future-epoch replay creates one generic undecryptable placeholder without decrypting or exposing future plaintext
- later valid replay can enrich sparse earlier rows with quote/media dependency data without creating duplicates or overwriting trusted fields

## closure bar

EC-003 can close when direct evidence proves future-dated, future-epoch, and dependency-delayed inputs either clamp, reject, placeholder, or enrich safely without corrupting current group/message state.

## session classification

`needs_repo_evidence`; no production behavior gap was found for the shipped reject/placeholder/enrichment contract. One supporting smoke fixture was recovered.

## Device/Relay Proof Profile

- Profile for this session: host-only Go and Flutter proof.
- Real-device/relay proof is supporting only because the row behavior is deterministic in the Go validator, Flutter message handler, offline replay drain, and fake-network smoke.

## files changed

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- EC-003 closure docs

## exact tests and gates run

- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery' -v -count=1` passed.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name 'far future incoming timestamp is clamped to receive time|past current and near future timestamps retain chronological order'` passed (`+2`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS003 live skewed timestamps clamp far future and keep latest sane'` first failed because Charlie was not broadcast as a member before publishing; after fixture recovery, the rerun passed (`+1`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay enriches a missing quotedMessageId'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'inbox replay enriches a sparse live copy with quote and media'` passed (`+1`).
- `dart format --output=none --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart` passed.
- `git diff --check` passed.

## Recovery Input

- Blocker class: stale supporting fixture under strict sender validation.
- Failing command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS003 live skewed timestamps clamp far future and keep latest sane'`.
- Failure: recipients rejected Charlie's skewed messages as unknown-sender traffic because the test did not broadcast Charlie's member-added event before Charlie published.
- Recovery: add `alice.broadcastMemberAdded(groupId: groupId, newMember: charlie)` and pump before publishing skewed messages.
- Result: the rerun passed and keeps the smoke aligned with current membership hydration rules.

## scope guard

EC-003 does not claim durable future-key queue/key-sync repair, live decryption repair lifecycle, or retry-after-key-arrival semantics. Those remain in EK-005 and ER-004 until first-class queue/repair primitives exist.

## Final Execution Verdict

`accepted`: EC-003 is covered for shipped future-input handling. Future timestamps clamp or order safely, unknown live future epochs reject before delivery, offline future epochs create one safe placeholder without decrypting, and later valid replay dependencies enrich sparse prior rows without duplicate/corrupt state.
