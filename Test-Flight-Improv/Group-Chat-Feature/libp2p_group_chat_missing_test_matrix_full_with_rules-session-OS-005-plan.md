# OS-005 Store-And-Forward Encryption Evidence Plan

## Session Intake

- breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row: `OS-005 | Store-and-forward and mailbox peers keep offline content encrypted`
- disposition: `repo_external_proof`
- execution classification: `evidence-gated`
- local plan fallback: used after the spawned planning attempt no-progressed without leaving a reusable plan

## Current Evidence Hypothesis

The repo likely has enough adjacent proof to close only the shipped mailbox/storage privacy contract if evidence confirms all store-and-forward payload families stay encrypted or metadata-minimized:

- Go group inbox-store requests preserve opaque encrypted replay envelopes and avoid protected plaintext.
- Flutter pending group inbox retry rows persist encrypted replay JSON instead of protected message content or media key material.
- Group media objects are encrypted before relay upload and carry per-object decrypt metadata only inside encrypted group descriptors.
- Group invite payloads keep key material and private group state inside encrypted invite envelopes.
- Retrieval/drain paths decrypt and authorize content only on the recipient side.

The row must stay `Partial` or `blocked` if receipts are a required shipped group mailbox payload but lack store-and-forward encryption proof, if invite/media descriptor storage cannot be proven through mailbox paths, or if live store-and-forward proof requires unavailable device/relay fixtures.

## Scope

Evidence first. Add code or tests only if inspection finds a small missing assertion in an already-shipped storage privacy owner.

Inspect:

- Flutter store/retry/drain owners:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/domain/models/group_offline_replay_envelope.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
- Invite and media storage privacy owners:
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - group media upload/download/send/replay paths
- Go/relay mailbox owners:
  - `go-mknoon/node/group_inbox.go`
  - `go-mknoon/node/group_inbox_test.go`
  - `go-mknoon/node/pubsub_test.go`
  - `go-mknoon/bridge/bridge.go`
  - relay server group inbox tests if present
- Existing evidence docs:
  - EK-002, LP-007, MD-004, IJ-001, and `PREREQ-GROUP-OFFLINE-REPLAY` records in `test-inventory.md`

## Scope Guard

- Do not relabel OS-003 direct peer sync, OS-004 pagination/backpressure, OS-006 gap repair, MD-003/MD-004 media integrity/key separation, EK signature/epoch rows, NT-001 notification push privacy, or SP-002 metadata minimization as OS-005 closure.
- Do not require plaintext push-preview elimination beyond the already-owned notification privacy rows; OS-005 can accept metadata-minimized routing/preview fields only if protected content and secrets remain encrypted.
- Do not implement a new mailbox protocol in this session.
- Do not mark `Covered` unless text, media descriptors or media references, invite material, and any shipped receipt/store-forward family are covered or explicitly non-shipped/out of row scope with evidence.

## Acceptance Criteria

Accept as `covered` or `accepted_with_explicit_follow_up` only if evidence proves:

- Store-and-forward/mailbox requests carry group offline replay or invite payloads as encrypted/opaque envelopes.
- Storage peer-visible JSON omits protected message body, media encryption keys, invite secrets, group key material, private group state, and unauthorized group metadata.
- Group media content is encrypted before relay upload, and descriptors/key metadata needed to decrypt are protected inside encrypted group payloads.
- Recipient retrieval/drain decrypts and applies content only through authorized group replay paths.
- Any group receipts mentioned by the source row are either proven encrypted/minimized on the shipped path or shown to be not shipped on group mailbox storage.
- Direct Go/Flutter tests or accepted equivalent evidence exercise the above; real device/relay proof is recorded only when fixtures are configured.

Block or keep `Partial` if any required content family lacks proof or depends on missing device/relay fixtures.

## Evidence Commands

- `rg -n "GroupInboxStore|group:inboxStore|group_offline_replay|pending inbox retry|opaque encrypted replay|PreservesOpaqueReplayEnvelope|pushTitle|pushBody" lib test go-mknoon go-relay-server integration_test`
- `rg -n "receipt|read receipt|delivery_receipt|group.*receipt|receipt.*group" lib test go-mknoon integration_test`
- `rg -n "GroupInvitePayload|encrypted invite|recipientPeerId|groupKey|invitePermissions|joinMaterialRef" lib/features/groups test/features/groups`
- `rg -n "encryptionKeyBase64|encryptionNonce|encrypted blob|contentHash|media descriptor|group media" lib/features test/features integration_test`
- `cd go-mknoon && go test ./node ./bridge -run 'TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol|TestGroupRelayVisible|GroupInboxStore' -v`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "EK-002 pending inbox retry stores encrypted replay without protected plaintext"`
- `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --name "encrypted|privacy|join material|payload"`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "encrypted|replay|authorization|recipient|dedupe"`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name "inbox|replay|dedupe|media|invite|receipt"`
- `printenv FLUTTER_DEVICE_ID`
- `printenv MKNOON_RELAY_ADDRESSES`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

If configured device/relay proof is available:

- `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly`

## Session Gates

- Focused evidence commands above.
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Execution Evidence

- Store-and-forward/mailbox path search found first-class group inbox-store and relay-server group inbox owners: Flutter `group:inboxStore`, Go `GroupInboxStore`, relay `GroupInboxStore`, opaque `group_offline_replay` envelopes, retry owners, and cursor retrieval. The same search found push preview fields as optional metadata and existing tests asserting safe omission/minimization on privacy-sensitive paths.
- Group receipt search found no shipped group receipt/read-receipt mailbox payload surface. Hits were routing smoke criteria text, legacy 1:1 `delivery_receipt` ignore handling, and generic local transport acknowledgement wording. OS-005 therefore treats receipts as not shipped on the group mailbox storage path.
- Invite search found `GroupInvitePayload` v2 encrypted envelopes, `recipientPeerId` binding, encrypted direct send, and inbox fallback through `p2pService.storeInInbox`. Existing focused tests prove group key, join material, allowed devices, invite permissions, and join-material references stay inside encrypted invite payloads for both direct and inbox fallback.
- Media search found group media content hash and encryption metadata throughout upload, encrypted replay, live descriptors, download, and fan-out paths. Existing MD-004 evidence proves group media blobs are encrypted before relay upload with distinct per-object key/nonce metadata, and descriptors/key metadata needed to decrypt are carried only inside encrypted group payloads/replay.
- `cd go-mknoon && go test ./node ./bridge -run 'TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol|TestGroupRelayVisible|GroupInboxStore' -v`: PASS. This proves group inbox-store request JSON preserves the opaque replay envelope, omits protected plaintext fragments, uses the versioned inbox protocol, and bridge validation accepts group inbox store fields.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "EK-002 pending inbox retry stores encrypted replay without protected plaintext"`: PASS. This proves persisted pending inbox retry JSON and the attempted `group:inboxStore` command carry an encrypted `group_offline_replay` envelope and omit protected message body, invite/private-state fragments, media encryption keys, and plaintext push previews.
- `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --name "encrypted|privacy|join material|payload"`: PASS (3 selected tests). This proves invite payloads and inbox fallback keep group key, recipient binding, join material, and policy details inside encrypted invite payloads.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "encrypted|replay|authorization|recipient|dedupe"`: PASS (14 selected tests). This proves encrypted replay drains only through recipient-side decrypt/authorization/dedupe paths, preserves quote/media descriptors when valid, and skips invalid/future/unauthorized replay before unsafe persistence.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`: PASS (10 tests). This proves failed group inbox-store retry rows resend their stored payloads and clear retry state while maintaining deterministic persisted ordering.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name "inbox|replay|dedupe|media|invite|receipt"`: PASS (17 selected tests). This proves inbox replay convergence, duplicate suppression, reaction replay, media/replay recovery, and unread/read state behavior on the fake-network recovery path.
- `cd go-relay-server && go test ./... -run 'TestGroupInboxStore_PreservesOpaqueReplayEnvelopeAcrossInstances|TestRedisGroupInboxBackend_PreservesOpaqueReplayEnvelopeAcrossClients|TestForbiddenFieldClassifier' -v`: PASS. This proves relay in-memory and Redis group inbox backends preserve opaque replay envelopes across store/retrieve and that push preview canaries are rejected by the forbidden-field classifier.
- `printenv FLUTTER_DEVICE_ID`: empty.
- `printenv MKNOON_RELAY_ADDRESSES`: empty.
- `./scripts/run_test_gates.sh completeness-check`: PASS (`694/694 test files classified`).
- `git diff --check`: PASS.

## Execution Verdict

`accepted_with_explicit_follow_up`

The shipped store-and-forward/mailbox privacy contract is covered by repo evidence: group message and reaction replay payloads remain opaque/encrypted through client request, pending retry storage, relay in-memory storage, relay Redis storage, retrieval, and recipient-side decrypt/apply; group invite store fallback uses encrypted invite envelopes; group media blobs are encrypted before relay upload and decrypt metadata stays inside encrypted group payloads/replay; no production group receipt mailbox payload is currently shipped. Real device/relay packet-capture proof is supplemental and fixture-blocked until `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are configured.

## Done Criteria

- OS-005 has a truthful evidence verdict.
- Source matrix and `test-inventory.md` record the same row-level status and exact evidence or blocker.
- Session breakdown ledger records OS-005 as `accepted | closure-verified`, `accepted_with_explicit_follow_up | closure-verified`, or `blocked | prerequisite-blocked` according to the evidence.
