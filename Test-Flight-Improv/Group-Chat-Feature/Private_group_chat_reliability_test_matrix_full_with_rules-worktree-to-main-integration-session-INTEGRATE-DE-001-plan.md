# INTEGRATE-DE-001 Live Group PubSub Delivery Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-001 | Active members receive a live text message through group pubsub`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-001-plan.md` in `worktrees/full-rules-pipeline`.
- Source closure status: `accepted` / `covered`.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond DE-001.

## Integration Scope

Import only the missing DE-001 row-owned delta into main:

- Propagate the app-side `GroupMessage.timestamp` into the Flutter bridge `group:publish` payload.
- Carry the optional publish timestamp through the Go bridge and native PubSub publish path while keeping it out of arbitrary `extra` metadata.
- Add row-named GM-001 host smoke assertions proving Alice, Bob, and Charlie persist the same timestamp, group id, message id, sender id, and epoch for the live text message.
- Add `de001LiveDeliveryProof` criteria and live-harness verdict fields for `gm001`.
- Add missing-proof and timestamp-mismatch criteria regressions.
- Rebuild and verify the iOS Go binding for the live `gm001` proof.
- Update the worktree-to-main ledger and test inventory after verification.

Do not import DE-002+, ordering, offline replay, membership mutation, media, notification, relay, adjacent row tests, source matrix/session docs, or unrelated source-worktree changes.

## Verification Contract

- Focused DE-001 host smoke selector.
- Focused GM-001 criteria selector.
- Go bridge and Go node timestamp/extra preservation selectors.
- Scoped analyzer and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-DE-001 residual failures.
- `./scripts/run_test_gates.sh completeness-check`, preserving unrelated fake-network classification residuals.
- iOS 26.2 live `gm001` proof with exact simulator device ids and run id recorded.

## Execution Evidence

Imported row-owned production deltas in `bridge_group_helpers.dart`, `send_group_message_use_case.dart`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/node/pubsub.go`; imported row-owned tests/proof hooks in `go-mknoon/node/pubsub_test.go`, `group_messaging_smoke_test.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_real_harness.dart`, and `group_multi_party_device_criteria_test.dart`; rebuilt the iOS Go binding; updated `test-inventory.md` and this integration ledger. The first fresh live proof run `1779131095902` exposed missing harness proof fields and timestamp visibility; after importing the row-owned proof-map fields and rebuilding bindings, the rerun passed.

Passed verification:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-001'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-001'` (`+3`)
- `(cd go-mknoon && go test ./bridge -run 'TestGroupPublish_MediaOnly|TestGroupPublish_MissingFields|TestBuildGroupPublishOpts')` (`ok github.com/mknoon/go-mknoon/bridge 0.557s`)
- `(cd go-mknoon && go test ./node -run 'TestResolveGroupPublishTimestamp|TestBuildGroupMessageExtra')` (`ok github.com/mknoon/go-mknoon/node 0.564s`)
- `dart analyze lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/send_group_message_use_case.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
- `./scripts/ensure_go_ios_bindings.sh` passed; rebuilt iOS binding contains `requestedTimestampProvided` and `payloadTimestamp`.
- `git diff --check` passed before doc closure.

iOS 26.2 live proof evidence: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C` passed with run id `1779131896948` and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_mLaZQW`. Devices were Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`), Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`), and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`). Final result: `gm001 proof passed: gm001 verdicts valid for alice, bob, charlie`. Alice sent message id `gmp_1779131896948_gm001_aliceInitial_alice`, group id `f9dbd323-9690-4fc5-b31b-2a7976ff0e8d`, timestamp `2026-05-18T19:22:03.710965Z`, key epoch `1`, and observed Bob/Charlie receipt signals. Bob and Charlie each proved `matchedGroupId`, `matchedMessageId`, `matchedSenderPeerId`, `matchedTimestamp`, `matchedEpoch`, and `incomingVisible` with the same timestamp. Alice's native log includes `group:publish_debug` with `requestedTimestampProvided:true`, `payloadTimestamp:"2026-05-18T19:22:03.710965Z"`, and `topicPeers:2`.

Named gate evidence: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+195 -3` only on preserved non-DE-001 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`). The DE-001/GM-001 smoke selector passed inside that gate before the preserved failures. `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Verdict

Accepted. DE-001 is integrated with row-owned app/native timestamp propagation, host smoke proof, criteria and live-harness proof, iOS 26.2 live `gm001` evidence, inventory update, and ledger evidence.
