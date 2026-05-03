# RP-017 Session Plan - Removed peer isolation blocks continued publishing and dialing

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:33:55+02:00 | Local planner completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; source matrix RP-017 row; `test-inventory.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_authorization_forward_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/node/node.go` | Current policy is ignore/filter rather than a hard disconnect or downscore: `UpdateGroupConfig` replaces membership, validators reject removed senders as `non_member`, known-member dialing reads only current config members, and rendezvous discovery filters peers absent from current config. Planning required direct RP-017 publish-and-dial proof under that policy plus media/sync supporting gates before closure. | Add row-named tests for removed-peer live/raw publish rejection and post-removal dial/discovery exclusion; run focused Go and Flutter group gates; close docs only if the source row can move to `Covered`. |

## real scope

Close RP-017 for the shipped removed-member isolation policy: after member C is removed from the current group config, remaining peers ignore C as a non-member, do not include C in known-member or rendezvous discovery dialing, reject C's continued live/raw group publishes before accepted delivery or forwarding, exclude C from future key and inbox recipients, and avoid accepting future plaintext, media, or key material from C.

The shipped policy is `ignore/filter` at group membership boundaries. This session does not add a separate peer blocklist, libp2p peer-score penalty, or forced transport disconnect unless tests expose that the existing ignore/filter policy cannot satisfy the row.

## closure bar

RP-017 can close only when:

- a row-named Go test proves a removed peer's live/raw message, reaction, membership, metadata, and key-rotation publishes are rejected as non-member traffic before delivery or forwarding to remaining peers
- a row-named Go test proves `UpdateGroupConfig` removal excludes the removed peer from later known-member dialing and rendezvous discovery dialing while a remaining member remains eligible
- focused Flutter tests/gates prove app-layer removed-member sends, retries, inbox drains, media ACLs, and key updates do not accept future plaintext/media/key material, publish future traffic, or distribute future key/material to the removed peer
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`evidence-gated`, with targeted tests required because current evidence was partial.

## Device/Relay Proof Profile

- Profile for this session: `host-only` closure with supporting real-network/nightly evidence unconfigured.
- Live availability check run: `flutter devices --machine` at `2026-05-01T06:33:55+02:00`.
- Available device ids observed: `emulator-5554`, `00008030-001A6D2801BB802E`, `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, `macos`, `chrome`.
- Closure evidence required for RP-017: host-side Go/libp2p raw PubSub and discovery/dial tests plus host Flutter group application/integration gates. A single `FLUTTER_DEVICE_ID` is not sufficient to prove a three-party physical network capture, but the RP-017 matrix row can close on repo-local host proof because the expected policy explicitly allows peers to ignore C.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly`.

## files to touch

- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `go-mknoon/node/pubsub_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

## step-by-step implementation plan

1. Add a row-named Go test that reuses the existing raw PubSub removed-peer harness and asserts continued publishes from removed C are rejected before accepted group events or forwarding to another remaining peer.
2. Add a row-named Go test that starts local nodes, joins a group, removes C through `UpdateGroupConfig`, and proves later known-member dialing/discovery connects or keeps eligibility for the remaining member while leaving C disconnected and counted as an ignored non-member.
3. Run focused Go tests for RP-017 and adjacent validators/discovery helpers.
4. Run focused Flutter removed-member, media ACL, and group membership tests plus the canonical groups gate and full group integration gate.
5. Update source matrix, inventory, and breakdown only after tests prove the row-owned closure bar.

## exact tests and gates to run

- `cd go-mknoon && go test ./node -run 'TestRP017|TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate|TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse' -v`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member cannot send after self-removal cleanup'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'post-removal messaging - admin can still send to remaining members'`
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'MD-011 removed member is excluded from future media descriptors and downloads'`
- `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'MD-011 retry excludes a removed member from media ACLs and inbox recipients'`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- RP-017 row-named Go publish and dial/discovery tests pass.
- Focused Flutter removed-member and media/sync gates pass or unrelated failures are explicitly classified.
- Canonical `groups` gate and full group integration pass or unrelated failures are explicitly classified.
- Source matrix RP-017 row is `Covered`.
- `test-inventory.md` RP-017 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record RP-017 as accepted/Covered.

## scope guard

Do not add a broad libp2p peer blocklist, peer-score/downscore subsystem, ban/unban product policy, account/device registry, or packet-capture proof under RP-017. Do not claim that existing connections are forcibly torn down unless code and tests implement that behavior. This row closes the shipped policy that removed peers are ignored and filtered from group membership surfaces, not a separate moderation or transport-block feature.

## Dirty Worktree Snapshot

Captured at `2026-05-01T06:33:55+02:00`: the tree already contains prior rollout changes in matrix/breakdown docs, Go node/bridge files, Flutter group/invite files, many group tests, and untracked prior session plan files. RP-017 execution is scoped to `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub_test.go`, this plan, and RP-017 closure docs unless a focused test exposes a row-owned implementation gap.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T06:41:16+02:00 | Executor completed | `go-mknoon/node/pubsub_authorization_forward_test.go`; `go-mknoon/node/pubsub_test.go`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Added RP-017 row-named raw PubSub rejection proof and post-removal dial/discovery exclusion proof; updated stale future-media replay expectation to the safe undecryptable placeholder contract. | Update source matrix, inventory, and breakdown to `Covered`. |
| 2026-05-01T06:41:16+02:00 | Verification completed | Focused Go proof; focused Flutter removed-member/media/replay/key tests; `./scripts/run_test_gates.sh groups`; full groups integration; `git diff --check` | All required host-side RP-017 evidence passed; `group-real-network-nightly` remains unrun supporting evidence because the relay/device fixture is not configured. | Proceed to closure docs. |

## Final Execution Verdict

`accepted`: RP-017 is ready to mark `Covered` for the shipped ignore/filter removed-peer isolation policy. Row-named Go proof rejects continued removed-peer message, reaction, membership, metadata, and key-rotation publishes before accepted delivery or forwarding, and row-named discovery proof excludes the removed peer from known-member and rendezvous dials after `UpdateGroupConfig`. Focused Flutter removed-send, retry, inbox, key, and media gates prove future traffic, key material, media descriptors, downloads, and plaintext are not accepted for removed peers. A forced future-media replay with only an old epoch saves only an `undecryptable` placeholder and does not decrypt or download media. No forced transport disconnect, peer downscore, or real-network nightly proof is claimed.
