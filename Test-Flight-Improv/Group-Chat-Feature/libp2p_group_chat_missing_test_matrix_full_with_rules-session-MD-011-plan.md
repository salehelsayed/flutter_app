# MD-011 Session Plan: Removed Members Do Not Receive Future Media

## Final verdict

Session classification: `implementation-ready`.

MD-011 is not already closed by current repo evidence. The repo has adjacent primitives for member removal, post-removal key rotation, media encryption metadata, media `allowedPeers`, and relay-side group media ACLs, but no direct proof that a removed member is excluded from future group media descriptors, blob keys, relay download access, sync/replay decrypt, and local download/decrypt display after removal.

The next session should add focused RED tests first. Production changes are only in scope if those tests prove a real behavior gap.

## Final plan

### real scope

Plan exactly one row: `MD-011`.

In scope:

- Prove A removes C, rotates the group key, then sends future media.
- Prove remaining member B can receive and download that future media.
- Prove removed member C receives no live future media descriptor, no future blob key, no local media row, no `media:download` trigger, and no decrypted content.
- Prove C cannot process an epoch-2 replay envelope if a relay/sync path exposes the opaque replay record after C only has the old epoch.
- Prove future group media upload/retry paths build media relay `allowedPeers` and group inbox `recipientPeerIds` from the current post-removal member set, excluding C.
- Use existing Go relay media ACL coverage as server proof that a peer omitted from `allowedPeers` cannot download a group blob. Add only a narrow Go assertion if the implementation reviewer requires a row-named removed-member relay test.

Out of scope:

- MLS, per-device key packages, ban/unban policy, group-wide relay storage redesign, durable per-recipient group inbox filtering, new UI, media caching redesign, and unrelated MD rows.

### closure bar

Good enough for MD-011 in the current architecture means all of these are true in tests:

- After removal plus key rotation, C is absent from the current group member set before A uploads or sends future media.
- Future media upload `allowedPeers` excludes C.
- Future message `recipientPeerIds` excludes C.
- The live fake-network path delivers the future media descriptor to B, not C.
- The offline replay path is encrypted with the future epoch and C cannot decode it with only the old epoch; no media descriptor or attachment is persisted for C.
- If C somehow knows the blob id, relay-side media ACL rejects download because C is not in `allowedPeers`.
- C never reaches blob decrypt or display for the future media.

Device/real-relay proof is supplemental for release confidence. It should not be used to claim local closure unless the direct app and Go relay tests above pass.

### source of truth

- Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, `MD-011`.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, order `43`.
- Current test inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Gate source of truth: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is explanatory and says the script wins on disagreement.
- Current code and tests win over stale prose.

### session classification

`implementation-ready`.

Reason: current evidence shows a concrete coverage gap that local/fake-network and Go relay tests can close before device-lab proof. This is not externally blocked.

### exact problem statement

The source row says: C is removed before A sends media; after remove and rotate, C attempts download/decrypt from live, sync, and relay; C cannot access future media descriptors, keys, or decrypted content.

Current repo evidence proves adjacent behavior, but not this exact media path. The risk is that future group media may accidentally reuse stale membership for descriptor fanout, upload ACLs, inbox retry recipients, or replay processing, giving a removed member a future media descriptor or blob key even if general key rotation excludes that member.

The behavior that must stay unchanged: remaining members keep receiving media, removed members still receive the removal artifact needed for cleanup, and existing media MIME/size/hash/encryption protections continue to run.

### files and repos to inspect next

Production files:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/media.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/media.go`
- `go-relay-server/inbox.go`

Test files:

- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `go-mknoon/integration/media_test.go`
- `go-relay-server/media_test.go`

### existing tests covering this area

Existing adjacent coverage:

- `member_removal_integration_test.dart` proves removal updates local membership before rotation, rotated keys are not distributed to the removed peer, first post-removal text sends use the rotated epoch, and voluntary-leave replay recipients exclude the leaver.
- `group_info_wired_test.dart` proves the shipped remove-member UI updates config, stores the removal replay artifact, then rotates and distributes the new key only to remaining members.
- `group_membership_smoke_test.dart` proves removed members stop receiving ordinary future messages, cannot send after cleanup, and can rejoin only through explicit re-add flows.
- `group_media_fanout_test.dart` proves existing and newly added members receive image/video/voice media descriptors and one receiver auto-downloads.
- `retry_incomplete_group_uploads_use_case_test.dart` proves retry uses current members for `allowedPeers`, but only for a simple admin plus B setup, not a removed-C scenario.
- `foreground_group_push_drain_test.dart` proves media replay descriptors can trigger one download and that invalid media is rejected before display, but not after member removal.
- `go-mknoon/integration/media_test.go` and `go-relay-server/media_test.go` prove group media `allowedPeers` lets allowed peers download and rejects peers omitted from the list.

Missing direct MD-011 coverage:

- No test removes C, rotates, then sends future media and asserts C gets no descriptor, no key, no download, and no decrypted file.
- No test simulates a stale/removed C receiving an epoch-2 encrypted replay record and verifies decode fails before media persistence.
- No test explicitly checks future media upload/retry ACLs after a removal exclude C.

### regression/tests to add first

Add RED tests before production changes:

1. Add a `MD-011 removed-member future media exclusion` test in `test/features/groups/integration/group_media_fanout_test.dart`.
   - Create A/admin, B/remaining, C/removed with `GroupTestUser`.
   - Seed epoch 1 for all.
   - Remove C through the production removal flow or the existing helper, then rotate to epoch 2 using `rotateAndDistributeGroupKey` or by driving the same production primitives with `PassthroughCryptoBridge`.
   - Ensure B receives/saves epoch 2; ensure C does not.
   - Send image media from A after removal.
   - Assert B receives the message, persists one media descriptor, and auto-downloads as expected.
   - Assert C has no future message row, no media attachment row for that blob, no pending download, no `media:download`, no `blob:decrypt`, and no local decrypted file.
   - Inspect A's `group:publish` and `group:inboxStore` calls: media descriptor exists for the future message, replay `keyEpoch` is 2, and `recipientPeerIds` excludes C.

2. Add a replay/sync leak guard in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
   - Build an epoch-2 encrypted replay envelope carrying a media descriptor.
   - Give C stale group state plus only the old epoch-1 key.
   - Make C's bridge return that replay envelope from `group:inboxRetrieveCursor`.
   - Drain the group inbox for C.
   - Assert decode is skipped, no future message or media attachment is persisted, and no `media:download` or `blob:decrypt` runs.

3. Add a removed-member retry ACL regression in `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`.
   - Seed a failed outgoing media message for A with current members A and B only, and a removed C that is absent from the current member table.
   - Retry the incomplete upload.
   - Assert `uploadMediaFn.lastAllowedPeers` contains B and excludes A and C.
   - Assert final `group:inboxStore` `recipientPeerIds` excludes C.

4. Do not add a broad Go rewrite. First run the existing relay ACL tests:
   - `go-mknoon/integration/media_test.go` group media allowed-peers test.
   - `go-relay-server/media_test.go` group media unauthorized-peer tests.
   If the reviewer requires exact row-named relay proof, add one small subtest reusing the existing harness where C is described as a removed former member, omitted from `allowedPeers`, and `MediaDownload` is rejected.

### step-by-step implementation plan

1. Add the RED tests above without production changes.
2. Run only the new/focused direct tests and confirm whether they fail for the intended MD-011 reason.
3. If all focused tests pass on current code, make no production changes; keep the session evidence-only/tests-only.
4. If C receives live future media, fix the smallest observed path:
   - ensure removal unsubscribes C from local/fake live delivery after the removal artifact,
   - ensure live delivery mirrors current post-removal membership,
   - ensure the receiver ignores messages when local group/member cleanup has already happened.
5. If media upload or retry ACL includes C, fix the upload caller to re-read current group members after removal and before upload/retry.
6. If `recipientPeerIds` includes C, fix `_loadGroupSendMembership` or retry payload construction to use the current member table and exclude the sender and removed members.
7. If C persists a replayed future media descriptor, fix replay decode/handling so missing future epoch keys fail closed before `handleIncomingGroupMessage` and before media persistence.
8. If C can download a blob despite being omitted from `allowedPeers`, fix the media relay ACL path in `go-relay-server/media.go` or the client upload allowed-peers request in `go-mknoon/node/media.go`.
9. Re-run focused tests, then the required gates.
10. Stop after MD-011 is proven. Do not fold in MD-012 quarantine, MD-014 device matrix, or broader membership/ban redesign.

### risks and edge cases

- Removal artifact ordering: C may need the old-epoch removal replay to clean up, while future media must use the new epoch and exclude C.
- Stale local state: C may still have the group row and old key until cleanup, so replay must fail closed on unknown epoch 2.
- Upload succeeds but publish/inbox store fails: retry paths must still exclude C.
- Zero-peer send fallback: inbox custody must not add C back as a recipient.
- Duplicate delivery: if live plus replay both arrive at B, dedupe must not create duplicate media rows.
- Media auto-download: C must not enqueue downloads from a descriptor it should never persist.
- Relay ACL: group media blobs are protected by `allowedPeers`; group inbox records are opaque encrypted replay envelopes, not plaintext descriptors.

### exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
```

Go relay/media ACL checks:

```bash
(cd go-mknoon && go test ./integration -run 'TestRelayGroupMediaUploadDownload|TestRelayGroupMediaVoiceNote')
(cd go-relay-server && go test . -run 'TestGroupMediaUploadDownload|TestGroupMediaUnauthorizedPeer|TestGroupMediaNoAutoDelete')
```

Broad group gates:

```bash
flutter test --no-pub test/features/groups
flutter test --no-pub test/features/groups/integration
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Device/real-relay supplemental proof when hardware and relay fixtures are available:

```bash
flutter test --no-pub -d <device-id> integration_test/foreground_group_push_drain_test.dart
FLUTTER_DEVICE_ID=<device-id> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly
```

`SMOKE-GAP-05` is a matrix label for the media safety evidence bundle, not a runnable shell command.

### known-failure interpretation

- A failure in one of the new focused tests is actionable only when it shows C receiving future media descriptors, C being included in future upload/inbox recipients, C decoding future replay, or C downloading/decrypting/displaying future media.
- Existing unrelated dirty-tree compile failures must be named separately and not counted as MD-011 regressions.
- Missing simulator/device IDs, absent relay addresses, or unavailable multi-relay fixtures make the supplemental device/real-relay commands externally blocked, not failed MD-011 implementation.
- The known historical issue where broad feed tests can fail in unrelated `orbit_wired.dart` is not an MD-011 signal unless MD-011 changes touch that code.

### done criteria

- The new MD-011 tests fail before any needed production fix or are documented as passing on current code with exact assertions.
- All focused tests pass after the implementation.
- C is directly proven excluded from future media live delivery, retry upload ACLs, inbox recipients, replay decrypt, media download, blob decrypt, and local file display.
- Existing remaining-member media delivery still passes.
- Existing Go relay group media ACL proof passes.
- Broad group gates and completeness check pass or any unrelated pre-existing failures are documented with exact file/error.
- No docs claim MD-011 covered until the direct tests and required gates above have evidence.

### scope guard

Do not:

- redesign group membership, ban policy, MLS, key schedule, or device-scoped key packages;
- make group inbox server retrieval per-recipient unless a direct RED proves plaintext media descriptors escape through inbox retrieval;
- change media encryption format or existing MD-001 through MD-004 contracts;
- change notification previews or push payload format beyond what the direct MD-011 proof requires;
- update unrelated matrix rows.

If the RED tests pass on current production code, stop after tests and evidence. Do not manufacture production changes.

### accepted differences / intentionally out of scope

- Current group inbox relay retrieval is group-scoped. MD-011 closure relies on encrypted replay plus future key exclusion for inbox payload confidentiality, while media blob access relies on relay `allowedPeers`. This plan does not treat group inbox retrieval as a media descriptor ACL unless plaintext descriptors are exposed.
- Existing removal cleanup intentionally sends the removed peer the removal artifact under the old epoch. That is accepted because it is not future media and is needed for cleanup.
- Per-device removal remains a separate RP row.
- Device-lab and real multi-relay proof remain supplemental acceptance evidence unless the local tests reveal behavior that cannot be exercised without real transport.

### dependency impact

- MD-012 media quarantine and MD-014 device/simulator matrix should wait for MD-011 direct proof if they depend on future media visibility after removal.
- Any later relay hardening plan should preserve the MD-011 contract: omitted peers cannot download group media blobs, and missing future group keys fail closed before descriptor persistence.
- If this plan changes to add server-side group inbox ACLs, revisit group replay, push fanout, and offline recovery rows because that would broaden beyond MD-011.

## Structural blockers remaining

None. The plan has a direct regression-first path, bounded production scope, named files, exact gates, and a stop rule.

## Incremental details intentionally deferred

- Row-named Go relay test can be added only if reviewers do not accept existing `allowedPeers` relay tests plus app-side exclusion of removed C.
- Device/real-relay `group-real-network-nightly` proof is deferred until fixtures are available.

## Accepted differences intentionally left unchanged

- Group inbox relay retrieval remains group-scoped and opaque-encrypted.
- Removal artifacts can still reach the removed peer for cleanup before future key rotation.
- Broader ban/device/MLS work remains outside this session.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/media.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/media.go`
- `go-relay-server/inbox.go`
- `go-mknoon/integration/media_test.go`
- `go-relay-server/media_test.go`

## Why the plan is safe or unsafe to implement now

Safe to implement now as a tests-first session. The target behavior is narrow, the production seams already exist, and the missing proof can be added without broad architecture changes. The only unsafe path would be expanding the session into a group inbox redesign, ban system, MLS/device-key work, or device-lab-only acceptance before the focused local and Go relay tests prove what currently fails.
