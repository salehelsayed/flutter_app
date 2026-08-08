# 347 - GAP-N01 Prepared Ordinary Direct Media Blob Client Adoption

Status: **EXECUTION-READY / DEFAULT-OFF / NOT STANDALONE RELEASE-ELIGIBLE** (reviewed 2026-08-08)
Type: Modification
Baseline: Plan 346 commit `88bce42fe8b0a205a65dc3cbfb0e7dbdb3cc1d8d`
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5 requirements 1, 3, and 6 plus A-01/A-02/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01
Classification: implementation-ready, bounded default-off client adoption of Plans 345 and 346 for durably prepared ordinary direct composer/voice sends and their retries
Closure tier: focused host Dart/SQLCipher/Go/protocol tests, affected curated `1to1`, justified `core-host-all` and `feature-host-all`, Android binding verification, and one availability-bounded automated Android-pair proof; no per-plan full `host-all` and no iOS run

## Planning Progress

| Time | Role | Files inspected | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-08-08 | Evidence collection | Plans 345/346; GAP-N01/WP-01 report; media upload/download/retry/model/repository paths; DB v108/v110 stage/drain; relay/node/bridge strict APIs; gates and device harnesses | Current direct upload deletes the relay ciphertext after the call and restart retries can mint different bytes for the same blob ID. The receiver has no durable strict download/ACK obligation. | Define the smallest durable artifact/proof state joining Plans 345 and 346. |
| 2026-08-08 | Planner | ACK-custody expiry, Redis protected lane, account transfer, Plan 345 producer identities, external-share ordering, live device matrix | Keep one DB v111 custody table and two nullable v108 binding fields. Scope sender adoption to lanes with Plan 345 durable identity; defer marker-free external share and production cohort negotiation. | Write causal tests before implementation and keep both admissions off. |
| 2026-08-08 | Independent reviewers + arbiter | Draft v1 plus current push-capability registry, Sims runner, SQLCipher proof, gate arrays, exact test paths, migration/file ownership | Initial verdict `needs-fixes`. Removed the unsupported push-token capability design, duplicate crypto/full-manifest storage, separate device/SQLCipher harnesses, and external-share redesign; retained the narrow expiry ceiling as a required cross-resource invariant. | Execute the reviewed contract below against the Plan 346 production-source baseline while preserving inventoried user-owned work. |

## Problem And Evidence

- `uploadMedia` encrypts into a temporary artifact, sends that path, and deletes it when the transport call settles. It retains a plaintext render copy, not the exact ciphertext accepted by the relay (`lib/features/conversation/application/upload_media_use_case.dart:581-814`).
- `retryIncompleteUploads` explicitly handles the divergent-ciphertext race by invalidating a prior envelope when a retry creates a new key/nonce. There is no process-durable ciphertext generation to reopen (`lib/features/conversation/application/retry_incomplete_uploads_use_case.dart:245-258,769-820`).
- `MediaAttachment.contentHash` identifies encrypted bytes, while `MediaAttachment.size` is plaintext size. The model has no ciphertext size, relay expiry, strict custody contract, or source relay (`lib/features/conversation/domain/models/media_attachment.dart:19-295`).
- Plan 346 exposes additive strict upload, strict exact-tuple download, and source-pinned exact ACK fields. Native upload hashes/stats the file actually sent and refuses unsafe cross-relay continuation after the body starts (`lib/core/bridge/p2p_bridge_client.dart:1120-1410`; `go-mknoon/node/media.go`). No feature caller adopts those fields yet.
- The installed receive path uses proof-less download followed by an ID-only, fire-and-forget delete after local commit. It does not persist the concrete download source before ACK (`lib/features/conversation/application/download_media_use_case.dart`).
- v108 stores an immutable exact envelope and intentionally survives parent deletion, but it has no binding to the protected blobs referenced by that envelope (`lib/core/database/migrations/108_direct_inbox_custody_outbox.dart`). Plan 345's `dbStageOutgoingDirectMediaInboxCustody` is the existing atomic parent/attachment/envelope boundary (`lib/core/database/helpers/media_attachments_db_helpers.dart:1237-1530`).
- Protected media and protected inbox entries both currently receive seven-day leases. Because blob upload precedes envelope storage, the envelope can expire later than its earliest blob (`go-relay-server/media.go:20-29`; `go-relay-server/inbox.go:2482-2489`). A check after v108 transfer would be too late.
- The only existing recipient capability registry is attached to authenticated push-token registration (`go-relay-server/inbox.go:2252-2254,2597-2613`; `go-relay-server/push_token_store.go`). It is absent when push enrollment is absent and is not a general media-decoder capability. Plan 347 must not couple blob safety to notification permission/token state.
- Composer and voice flows have Plan 345 durable message/attachment identity before upload. Direct external share uploads before `sendChatMessage` and has no recoverable message identity at that point (`lib/features/share/application/share_batch_delivery_coordinator.dart:1277-1335`). Redesigning that producer is a separate slice, not a hidden prerequisite here.
- Plan 346's non-vacuous shell contract currently bans all feature adopters. Plan 347 must replace it with an exact positive allowlist for this bounded path while preserving all lower-layer and default-off checks (`scripts/test/relay_media_custody_contract_test.sh`).

## Graph Grounding Snapshot

- Query: `python3 graphify-arch/tdd_context.py query "Plan 347 UploadMediaUseCase RetryIncompleteUploadsUseCase MediaAttachmentRepositoryImpl P2PBridgeClient media custody strict upload strict download source relay ACK proof direct_inbox_custody_outbox v108 dbStageOutgoingDirectMediaInboxCustody exact ciphertext restart expiry" --profile tdd --budget 700`.
- Result: `confidence=anchored`, fingerprint `a16cb6ba3a84529f`.
- Anchors: `dbStageOutgoingDirectMediaInboxCustody`, `MediaAttachmentRepositoryImpl`, and DB v108 `direct_inbox_custody_outbox`.
- Graphify supplied the shortlist; native/relay/generated and exact gate facts were verified in source.
- This is a documentation-only planning change. Do not refresh Graphify until a coherent app-owned implementation exists.

## Scope Contract And Guard

In scope:

- Fresh or resumed **ordinary direct** composer media and voice sends that already possess Plan 345's durable message ID, complete attachment-ID manifest intent, and current attachment projection.
- `retryIncompleteUploads` and `retryFailedMessages` convergence for those exact prepared rows.
- Receiving any valid ordinary-direct strict blob commitment, strict download, durable local commit, and exact source-pinned ACK retry.
- A default-false client selector, `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED`. Test composition may enable it only for an explicitly upgraded Android pair; production remains false.
- One app-owned ciphertext artifact per outgoing attachment ID, prepared once and reopened/re-hashed across foreground, lifecycle, ambiguity, and process restart.
- One message-wide strict-generation boundary: prepare unique candidates for the complete Plan 345 manifest, then atomically publish all attachment crypto projections and all `outgoing_prepared` v111 rows before any LAN/relay request. A retry without that complete generation is legacy-only.
- DB v111 independent custody state with no parent foreign key, plus nullable v108 manifest-hash/earliest-expiry fields. Historical v108 rows remain null and remain on Plan 345's legacy blob behavior.
- A typed public `blobCustody` commitment in each encrypted attachment descriptor and a canonical, domain-separated manifest hash bound atomically to v108.
- Plan 346 strict upload, strict download, and source-pinned ACK APIs, without reimplementing relay selection in Dart.
- One optional `custodyExpiresAtOrBeforeMs` on strict v108 inbox store. The relay may shorten, never extend, the normal expiry and returns the exact persisted value. Omission preserves text/reaction behavior.
- A sibling media-only expiry-bounded inbox capability implemented by the production P2P owner. The existing broadly implemented `AckOrExpiryInboxStore` signature remains unchanged for text/reaction callers and fakes.
- Lifecycle/bootstrap drain, account-transfer table/file inventory, bounded orphan cleanup, fixed-cardinality diagnostics, exact gate registration, Android bindings, and reuse of the existing Sims two-peer Android runner.

Out of scope:

- Marker-free direct external share sender adoption. It remains on the legacy blob path until a later plan gives it durable pre-upload message/attachment identity; Plan 345's final envelope custody remains unchanged.
- Private/disappearing media, group/announcement media, posts, avatars, historical backfill, edits/deletes, linked-device fanout, or group per-member ACK.
- A recipient capability registry, push-token schema change, unsupported-recipient relay error, or automatic strict-to-legacy negotiation. Production cohort/capability rollout remains WP-07 work.
- Enabling `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED`, `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED`, or the client selector in production, deploying/restarting a relay, mutating production Redis, or claiming mixed-version activation.
- New media/inbox protocol IDs, protected list APIs, relay replication, resumable chunks, object storage, a new scheduler, or a new mobile-device harness.
- iOS build/simulator/device work and per-plan full `host-all`.

Hard `Do not`:

- Do not infer strict eligibility from `allowedPeers == null`, MIME, attachment shape, an untrusted wire field, or the build flag alone. A fresh Plan 347 producer must atomically establish the complete v111 generation before its first LAN or relay request; retry may only reopen that existing generation.
- Do not enable strict sender behavior for external share, private/disappearing, group, historical, or no-intent rows.
- Do not mint v111 from an in-flight/pre-upgrade v110 row that has no v111 generation. Even when only part of its attachment manifest has legacy upload metadata, the entire attempt remains on Plan 345's legacy blob path.
- Do not re-encrypt an attachment ID while a valid prepared/uploaded/v108 custody generation exists.
- Do not fall back to legacy upload after any strict attempt, including admission-off, full, timeout, proof mismatch, or ambiguous commit. The prepared row remains locally owned.
- Do not stage or send a strict v108 envelope until every referenced blob has a persisted exact upload proof with a safe positive remaining lifetime.
- Do not complete v108 custody on an absent, non-positive, or later-than-blob envelope expiry.
- Do not ACK a strict blob before local file and DB commit plus durable ACK-obligation commit; do not fan ACK across relays.
- Do not put local paths, relay IDs, store status, keys, or nonces into the public commitment or new Plan 347 diagnostics/metrics. Preserve existing lower-layer Plan 346 telemetry rather than expanding this plan into a logging rewrite.
- Do not delete a ciphertext artifact directly from prepared/uploaded/v108 state. Only an atomic transition that proves exact v108 completion, explicit pre-v108 cancellation with verified v108 absence, or exact proof-expiry terminalization with verified v108 absence may publish `outgoing_cleanup_pending`; the idempotent cleanup owner may then remove the file.

## Minimal Data And Wire Contract

### DB v111

Add `direct_media_blob_custody` keyed by `attachment_id`, with constrained fields for:

- `message_id`, `direction` (`outgoing|incoming`), state, and optional bound v108 incarnation;
- outgoing recipient and app-owned relative ciphertext path;
- custody kind/contract, lowercase ciphertext SHA-256, positive ciphertext size, opaque transport MIME, exact relay expiry, and upload/source relay where applicable;
- incoming ACK state/source relay and bounded retry timestamps;
- created/updated timestamps.

Do **not** duplicate attachment encryption keys/nonces or the full canonical manifest in v111. Existing attachment rows retain crypto metadata; v111 owns transport artifact/proof/ACK state. It deliberately has no foreign key so cleanup and ACK obligations survive parent deletion.

Required states and transitions:

| State | Durable authority | Permitted next state |
|---|---|---|
| `outgoing_prepared` | verified ciphertext path/hash/size/MIME; no relay proof | exact retry, `outgoing_stored`, or explicit pre-v108 cancellation to cleanup |
| `outgoing_stored` | complete strict upload receipt plus exact artifact | atomic v108 bind/retry; exact v108 completion to cleanup when bound; or explicit cancellation/proof-expiry terminalization to cleanup only with verified v108 absence |
| `outgoing_cleanup_pending` | exact v108 owner was retired atomically, or exact v108 absence plus local cancellation/expired proof was recorded; file removal remains | row removal only after verified artifact absence |
| `incoming_committed` | exact wire commitment; no ACK source yet | strict download or exact expiry |
| `incoming_ack_pending` | durable local commit plus exact source relay/proof | same-source ACK retry, then row removal |

Parent deletion before v108 exists cancels a local prepared send through a state transition and later cleanup; it does not continue sending an erased message. Parent deletion after v108 ownership or after incoming local commit cannot erase the independent cleanup/ACK obligation.

Extend `direct_inbox_custody_outbox` additively with nullable:

- `media_blob_manifest_hash` — 64 lowercase hex;
- `media_blob_expires_at_ms` — positive earliest blob expiry only when the hash is present.

Both are null for text and pre-v111/historical rows. No backfill or promotion is allowed. At strict stage, one transaction assigns the exact v108 incarnation to the complete `outgoing_stored` row set, recomputes the canonical manifest hash/earliest expiry, stages the exact envelope, and writes v108. Completion recomputes against rows bound to that exact incarnation, deletes v108, and marks the same rows `outgoing_cleanup_pending` atomically. The domain-separated hash already binds list length, so a separate count column would be redundant.

### Public blob commitment

Each encrypted attachment JSON may carry `blobCustody` with exactly:

- `kind=direct_media_blob_v1`
- `contract=ack_or_expiry_v1`
- `contentHash` — 64 lowercase hex over ciphertext
- `ciphertextSize` — actual positive encrypted file size
- `transportMime=application/octet-stream`
- `expiresAtMs` — exact positive upload-proof expiry

The attachment ID remains the blob identity already present in the descriptor. `MediaAttachment.size` remains plaintext size and must not substitute for `ciphertextSize`.

The v108 manifest hash is SHA-256 over UTF-8 `jsonEncode(['mknoon.direct-media-blob-manifest.v1', ...sorted blob projections])`. Blobs sort lexicographically by attachment ID, and each projection is the positional array `[attachmentId, kind, contract, contentHash, ciphertextSize, transportMime, expiresAtMs]`; no map-key ordering can change the digest. The same pure helper is used by sender model serialization and DB revalidation. Relay ID/store status/path/key/nonce never enter it.

### Expiry coupling

- Inject the clock in tests. Refuse strict envelope staging when any upload proof is expired or lacks the existing bounded initial-v108-store timeout budget; do not add another runtime tuning knob. Relay time remains authoritative, so skew can cause conservative refusal but never a later envelope lease.
- Pass the persisted earliest blob expiry as `custodyExpiresAtOrBeforeMs` on every strict v108 store/retry.
- Relay validation requires `now < ceiling <= now + maxMessageAge`. It persists per-entry expiry `min(now + maxMessageAge, ceiling)` for a new protected row and returns that exact value for stored/duplicate.
- An exact duplicate preserves its original expiry. A request with a different ceiling is an identity/proof conflict; it never refreshes or narrows accepted authority silently.
- Protected pruning uses per-entry expiry when present and the historical timestamp-derived expiry when absent. Legacy text/reaction requests omit the field and retain existing bytes/expiry behavior.
- v108 retires only when `0 < envelopeExpiresAtMs <= mediaBlobExpiresAtMs`. At the blob bound, automatic sending stops truthfully; it does not mutate immutable bytes, synthesize success, or re-encrypt the same logical attempt.
- An incoming ACK obligation may retire without relay contact only at its persisted exact expiry; that is expiry convergence, not a synthetic ACK.

A longer protected-blob TTL plus client preflight was considered and rejected as the supposedly leaner alternative. It would introduce a second relay retention policy, increase protected capacity pressure, make the client hard-code the relay inbox lease, and strand a suspended send until the old blob expires when its remaining lifetime falls below a full envelope lease. The sender cannot cancel that recipient-authorized blob through Plan 346's ACK (`req.To` must equal the authenticated recipient). One optional ceiling on the existing strict inbox request preserves current retention and lets the relay authoritatively shorten only the dependent envelope.

## Activation And Compatibility Contract

| State | Required behavior |
|---|---|
| Client selector false (all production configurations in this plan) | Existing legacy upload/download/delete and envelope shape; no DB v111 strict generation or wire commitment. Existing v108 envelope custody remains active. |
| Selector true, exact Plan 345 prepared composer/voice identity, upgraded test recipient, and both required relay admissions true | Prepare/reopen exact ciphertext, use strict upload, bind proof to v108, and use strict receive/ACK. |
| Selector true but either required relay admission is disabled/full/error/ambiguous | Retain local exact artifact and state; no legacy fallback and no envelope custody claim. |
| Selector true but caller is external-share/private/group/historical/no-intent | Legacy path remains selected before strict preparation or request. |
| Old/legacy envelope on upgraded receiver | Existing legacy download/delete remains byte-compatible. |
| Strict envelope on upgraded receiver | Validate complete commitment and use strict download/ACK only; never downgrade. |

Plan 347 proves the strict path only with a controlled upgraded pair. It does not solve production mixed-recipient selection. WP-07 must add an authenticated capability/cohort source independent of push-token enrollment, rollout ordering, and old-client rollback evidence before either production flag may be enabled.

## Test Contract

The production-source baseline is Plan 346 commit `88bce42f`. Before execution, inventory and preserve any other user-owned work; no post-baseline production-code change may be silently treated as part of Plan 347. Test names below are literal selectors to add or extend.

| Case | Behavior | Tier / fixture | Named test / proof | HEAD -> GREEN | Representative mutation | Registration / gate |
|---|---|---|---|---|---|---|
| TC-347-01 | DB v111 and nullable v108 binding fields migrate from v110 without backfill, survive reopen/run-twice, enforce state combinations, and establish the one-way v111 floor | Host real SQLite plus real Android SQLCipher / production registry, v108-v110 rows, wrong key and rollback snapshots | `test/core/database/migrations/111_direct_media_blob_custody_test.dart::TC-347-01 DB v111 adds independent blob custody without historical promotion`; extend `integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart::TC-347-01 Android SQLCipher v110-to-v111 blob custody survives reopen` | HEAD lacks table/columns/version -> exact schema, constraints, registry and prior rows are preserved | Add FK cascade, backfill a v108 row, loosen conditional constraints, omit registry, or allow downgrade -> red | Add the new host migration file once to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; reuse existing Android discovery path; AUTO core |
| TC-347-01b | Every existing Android SQLCipher proof with a literal current-version pin advances deliberately to v111 while historical v108-v110 boundary literals remain allowlisted | Same explicit available Android ID / seven existing encrypted production-registry proofs, including release plugin boundary | `integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart`, `integration_test/direct_notification_durability_sqlcipher_proof_test.dart`, `integration_test/direct_reaction_inbox_custody_outbox_sqlcipher_proof_test.dart`, `integration_test/group_exit_intents_sqlcipher_proof_test.dart`, `integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart`, `integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart`, and `integration_test/group_self_removed_marker_sqlcipher_proof_test.dart` | Literal current pins are 110 -> all seven open current v111 and preserve their historical migration assertions | Blind global `110 -> 111`, skip a proof, weaken wrong-key/reopen, or rewrite a historical boundary literal -> red | Existing reliability discovery paths; six `flutter test -d` commands plus the existing PB266 `connectedReleaseAndroidTest` leg on the same explicit Android ID |
| TC-347-02 | A fresh Plan 347 producer establishes the complete strict generation before network, then restart reopens byte-identical ciphertext after ambiguous upload; LAN/relay, generic saves, and concurrent preparers preserve it | Host application / prepared voice plus two-blob composer, real temp files, fake bridge bodies, deleted/mutated original plaintext, ENOSPC/write failpoint, recreated owners, same-ID barriers, generic key/hash mutation | `test/features/conversation/application/send_voice_message_use_case_test.dart::TC-347-02 fresh prepared voice ambiguity then restart reuses one durable ciphertext`; `test/features/conversation/application/upload_media_use_case_test.dart::TC-347-02b prepared LAN and strict relay bytes are identical`; `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::TC-347-02c concurrent preparers adopt one artifact generation` and `::TC-347-02d active blob generation rejects generic crypto mutation`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::TC-347-02e complete strict manifest publishes before first network` | Baseline deletes transient ciphertext and can rotate metadata -> complete v111 generation precedes network; retry succeeds with original source removed; one CAS winner survives; write failure has no DB/network effect; generic saves cannot change key/nonce/hash/path | Re-encrypt from retained key/changed source, trust stored hash without re-stat, publish only blob A, send after ENOSPC/before full DB commit, reuse one final path, allow generic mutation, or let loser overwrite/delete winner -> red | Existing `1to1` registrations and AUTO feature; fresh voice TC-347-02 is first causal RED |
| TC-347-03 | Strict upload sends the exact Plan 346 tuple and accepts only a complete exact relay receipt; failed/ambiguous calls retain local ownership with no fallback | Host application + Dart bridge / real file, typed prepared identity, strict/legacy spies, full/error response table | `test/features/conversation/application/upload_media_use_case_test.dart::TC-347-03 strict prepared direct upload accepts exact relay proof`; `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart::TC-347-03b strict failed retry reopens exact generation without legacy fallback`; Plan 346 bridge/native sentinels | Baseline omits strict fields/proof persistence -> kind/contract/hash/actual size/opaque MIME and `stored|duplicate` are validated; expiry/relay proof persists atomically | Persist unused raw store status, accept broad `ok`, plaintext size, real MIME, changed relay, missing expiry, or call legacy after strict error -> red | Existing `1to1`/AUTO feature plus existing media-custody Go gate |
| TC-347-04 | Complete multi-blob commitment and v108 binding are one authority; pre-v111 rows remain legacy; every live/inbox/lifecycle completion hands exact rows to cleanup atomically | Host real SQLite + model/application / two attachments, crossed/partial/duplicate IDs, exact incarnation CAS, parent deletion, live/inbox winner table | `test/features/conversation/domain/models/message_payload_test.dart::TC-347-04 blob custody canonical wire and manifest hash`; `test/core/database/helpers/media_attachments_db_helpers_test.dart::TC-347-04 strict blob manifest binds and completes exact v108 atomically`; `test/features/conversation/application/send_chat_message_use_case_test.dart::TC-347-04b strict ordinary media requires complete stored proof before egress` | HEAD has no commitment/binding -> exact sorted projection, hash/expiry, all-or-zero stage, and one-transaction v108-to-cleanup handoff on every winner | Sort by caller order, use plaintext size, patch v108 later, mix generations, stage a successful prefix, bypass cleanup on live ACK/duplicate drain, or promote historical v108 -> red | Existing core/feature/`1to1` paths; no new manual registration |
| TC-347-05 | Strict v108 store expiry cannot exceed earliest blob expiry; both protected row and atomic legacy shadow obey that expiry; exact duplicates cannot refresh/change it; omitted text/reaction fields are unchanged | Host Go protocol + Redis/miniredis process handoff + Dart bridge/application / deterministic relay/client clock offsets, protected duplicate, legacy-only promotion, destructive legacy retrieve/count/stats, and proof table | `go-relay-server/ack_custody_protocol_test.go::TestRelayNotificationClosure_DirectMediaEnvelopeExpiryCeiling`; extend `go-relay-server/redis_failover_integration_test.go::TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace`; `go-mknoon/node/inbox_ack_custody_test.go::TestInboxAckCustodyMediaExpiryCeiling`; `go-mknoon/bridge/inbox_ack_custody_test.go::TestInboxStoreMediaExpiryCeilingBridgeContract`; `test/core/bridge/p2p_bridge_client_test.dart::TC-347-05 inbox custody media expiry ceiling is exact and optional`; `test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart::TC-347-05b media v108 retires only on envelope expiry at or before blob bound` | Baseline derives expiry only from timestamp -> both copies prune at exact cap across restart/read/count/stats; absent/zero/later app proof retains v108+blob rows; valid proof transitions atomically; omitted field keeps text/reaction | Expire protected only, let legacy retrieve outlive ceiling, refresh/narrow duplicate, promote legacy-only without exact ceiling, compare after transfer, trust client clock, or retire v108 on missing/later proof -> red | Extend existing ACK-custody Go gate and Dart core/1:1 paths; update exact `-list`/PASS counts so selectors are non-vacuous |
| TC-347-06 | One narrow incoming transaction commits parent, all strict attachments, and all `incoming_committed` rows before notification/receipt/inbox ACK; relay download later commits local bytes and ACK state/source atomically; verified LAN-local adoption converges by expiry | Host feature/repository + native sentinels / multi-attachment strict/legacy table, duplicate replay, corruption/file+DB failpoints, observer spies, concurrent workers, changed relay order, staged LAN part | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::TC-347-06 incoming strict parent attachments and custody commit atomically`; `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart::TC-347-06a strict blob commitment publishes only after atomic stage and legacy remains compatible`; `test/features/conversation/application/download_media_use_case_test.dart::TC-347-06b strict download commits before same-source ACK`; repository `::TC-347-06c incoming ACK obligation survives restart and parent deletion`; download `::TC-347-06d verified LAN adoption suppresses strict ACK until expiry` | Baseline saves parent before attachments and performs proof-less download/ID delete -> partial failure publishes nothing/no side effects; exact duplicate adopts; file durable then attachment+source+ACK row commit together; LAN has no delete/ACK | Save parent first, emit delivery receipt/notification/inbox ACK before combined commit, accept one valid attachment from partial manifest, split attachment/ACK-state transactions, fan out, let concurrent worker erase source, or ID-delete LAN-local strict blob -> red | Existing `1to1`/AUTO feature plus Plan 346 node/bridge sentinels |
| TC-347-07 | Lifecycle, explicit cancellation/proof-expiry, cleanup, production bootstrap, and account transfer preserve exact authority and only reap unreferenced identity-scoped artifacts | Host core/feature / prepared/stored/v108/cleanup/ACK states, same-lock file-before-row barrier, path attacks, file/DB failpoints, transfer manifest/import round trip | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::TC-347-07 blob custody lifecycle and authority-safe cleanup`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::TC-347-07b production composes one blob custody drain`; `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart::TC-347-07c resume orders blob recovery before mutable upload retry`; extend `test/features/account_migration/application/migration_database_schema_inventory_test.dart`, `test/features/account_migration/application/migration_file_manifest_builder_test.dart`, `test/features/account_migration/application/migration_database_active_importer_test.dart`, and `test/features/account_migration/application/account_migration_end_to_end_test.dart` with `TC-347-07` selectors | Baseline inventories neither v111 nor ciphertext artifacts -> bootstrap drains exact states, cancellation/expiry are explicit, transfer preserves row/file/binding, and cleanup under the same lifecycle lock cannot steal the file-before-row publication window | Delete a referenced/newly published artifact, omit table/file, accept absolute/traversal/cross-identity path, continue a deleted pre-v108 message, skip expired terminalization, or lose ACK row -> red | Existing core/feature paths; exact focused commands, no new manual test path |
| TC-347-08 | Adoption is default-off and bounded to fresh Plan 347 composer/voice generation plus reopen-only retry; v110-without-v111 (including partial legacy success), external-share/private/group/historical and pre-v111 v108 remain wholly legacy; no push coupling exists | Host source-contract + application preservation / flag matrix, fresh prepared producers, pre-upgrade two-blob partial crossing, exact helper/token inventories | Revised `scripts/test/relay_media_custody_contract_test.sh`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::TC-347-08 prepared ordinary composer selects strict blob coordinator`; `test/features/conversation/application/send_voice_message_use_case_test.dart::TC-347-08b prepared ordinary voice selects strict blob coordinator`; `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart::TC-347-08c absent-v111 partial legacy attempt never promotes to strict`; `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-347-08d external share remains legacy`; `test/features/conversation/application/upload_media_use_case_test.dart::TC-347-08e disabled and excluded callers preserve legacy bytes`; existing fresh-key retry preservation with selector false | Baseline has no adopter -> GREEN fresh producers select strict; retry only reopens complete v111; every excluded/pre-upgrade attempt stays byte-compatible legacy | Mint v111 in generic retry, mix first legacy/second strict, default flag on, infer from ACL, let push token imply support, allow network helpers outside coordinator/download owner, or change disabled retry -> red | Dedicated shell under `1to1`/`all`; existing feature/1:1 paths; strict network-helper allowlist is only coordinator plus strict download/ACK owner, while a separate schema-token allowlist covers other typed owners |
| TC-347-09 | Two upgraded Android peers recover exact blob plus v108 envelope after sender process restart; receiver proves durable bytes and source-pinned ACK removes protected authority | Availability-bounded device / USB Android sender + Android emulator receiver, reachable test-only Go relay fixture using production handlers with ephemeral Redis/media roots, dedicated build profile, existing dispatcher plus campaign module | Sims capability `android.direct_media_blob_custody`; profile/build `android.e2e.direct_media_custody` / `build.android.e2e.direct_media_custody`; `integration_test/scripts/run_direct_media_blob_custody_sims.dart`; `integration_test/scripts/android_direct_media_blob_custody_campaign.dart`; `integration_test/support/android_direct_media_blob_custody_evidence.dart`; `test/features/conversation/integration/android_direct_media_blob_custody_campaign_test.dart`; `go-relay-server/direct_media_blob_custody_device_fixture_test.go::TestDirectMediaBlobCustodyDeviceFixtureContract`; `scripts/test/direct_media_blob_custody_prebuilt_runner_contract_test.sh` | Baseline cannot create strict commitment/reopen ciphertext -> adapter starts fixture with both relay admissions, injects exact address before central build, executes preparation then scenario, and finally tears down; validator-bound pair proves upload, kill/restart, exact envelope retry, download/decrypt/reopen, ACK and post-ACK absence | Use external/production relay, leave fixture alive, build inside device runner, omit address/admission/profile identity, use main profile, retain only memory evidence, rely on taps, or assert UI without relay state -> red | Add campaign host test once to both 1:1 arrays; extend Sims manifest/proof/discovery and media shell gate; adapter must call central Sims prepare and execute as two operations; no second mobile harness/iOS |

### First Causal RED

Add TC-347-02 to the existing voice sender test using only current Plan 345 models/callable producer, current `UploadMediaFn`, a real plaintext fixture, and the current raw fake bridge. Let the fresh producer reach an ambiguous first upload, delete or mutate the original plaintext, recreate DB/repository/retry owners, and retry the same intent/attachment ID. Compare captured encrypted bodies and persisted crypto metadata.

```bash
flutter test \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'TC-347-02 fresh prepared voice ambiguity then restart reuses one durable ciphertext'
```

Expected on the production-source baseline: the test compiles and reaches behavior, but the first encrypted artifact is deleted and restart either cannot recover or mints a different generation. It must not import DB v111 or a future production type. Retain this RED receipt and later re-red it by restoring re-encryption or post-ambiguity deletion. The separate TC-347-08c must stay GREEN and prove that retry never creates strict state for an absent-v111 pre-upgrade attempt.

## Implementation Steps

1. Confirm HEAD/baseline `88bce42f`, inventory all dirty paths without altering user-owned work, verify that no post-baseline production change is being absorbed, rerun the anchored Graphify TDD query, and stop if another migration owns v111.
2. Add fresh-producer TC-347-02 first. Capture the behavioral RED, then keep the exact selector-false fresh-key test and TC-347-08c absent-v111/pre-upgrade retry preservation green.
3. Add DB v111, the two nullable v108 columns, current-version registry/floor updates, constrained model/helpers, and one identity-scoped app-owned ciphertext directory. Under the existing media lifecycle lock, prepare unique candidate files for the complete Plan 345 attachment manifest, write/flush/rename/re-hash them, then use one SQL transaction to publish every attachment crypto projection and every `outgoing_prepared` row. No LAN/relay request occurs before that commit. A file without a row after process death is an orphan; a row without a verified file fails closed. Reject absolute, traversal, symlink-escape, and cross-identity paths.
4. Add one typed prepared-direct custody coordinator/context used only by fresh Plan 345 composer/voice producers. It establishes the complete generation, CAS-adopts a concurrent same-ID winner, calls the Plan 346 strict upload helper, validates the receipt, and transitions each row to `outgoing_stored`; after blob A succeeds and B is interrupted, restart skips A and reopens B. Retry owners may call the coordinator only with an already complete v111 generation and must never mint one. A loser never overwrites/deletes the winner. Keep generic `UploadMediaFn` legacy semantics for excluded/pre-upgrade callers.
5. Add optional `blobCustody` model serialization and one pure canonical manifest-hash helper. Extend the existing combined media staging transaction to revalidate the Plan 345 intent/current rows, bind exact `outgoing_stored` rows to the v108 incarnation, and commit envelope/hash/earliest expiry together. Add the atomic v108 completion-to-cleanup helper for live, inbox, and lifecycle winners.
6. Add a sibling media-only expiry-bounded inbox capability; do not widen `AckOrExpiryInboxStore` or its unrelated text/reaction fakes. Thread its optional `custodyExpiresAtOrBeforeMs` through the existing Dart bridge JSON, Go bridge/node request, relay handler, protected Redis row, and same-entry legacy shadow. Reuse the current protocol/action. Preserve timestamp-derived expiry for omission; refuse ceiling-bearing legacy-only promotion and duplicate ceiling changes; prune both copies across retrieve/count/stats. Add the application drain proof plus literal discovery/PASS checks for every new tagged/node/bridge test.
7. Add one narrow strict-incoming repository transaction that commits parent, the complete attachment projection, and every `incoming_committed` row before cache/stream publication, notification promotion, delivery receipt, or inbox ACK; exact duplicate replay adopts and mismatch refuses. For relay download, make the durable file first, then commit attachment completion plus exact source and `incoming_ack_pending` in one SQL transaction before ACKing that source. For verified LAN-local strict bytes, commit locally but retain source-less `incoming_committed` until expiry; suppress source-pinned ACK and the current legacy ID-only delete. Coalesce concurrent workers and reuse lifecycle/bootstrap retry.
8. Add exact pre-v108 cancellation, proof-expiry, v108-retirement, and cleanup transitions; only `outgoing_cleanup_pending` may unlink. Add production bootstrap/resume ordering, account-transfer schema/file inventory, and fixed-cardinality counts/outcomes. Never log proof values or IDs.
9. Replace Plan 346's no-adopter shell clause with two inventories: only the custody coordinator and strict download/ACK owner may call `callP2PMedia*` with strict arguments; a separate exact schema-token allowlist covers prepared producers, retry, staging, incoming repository, and bootstrap typed-state owners. Keep lower-layer/default-off checks and all exclusions. Add the migration and campaign host-contract tests once each to both manual 1:1 arrays.
10. Extend all seven current-version SQLCipher proofs. Add `android.e2e.direct_media_custody` with only `E2E_TEST_MODE=true` and `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true`, plus its build capability. Add a test-only tagged Go fixture process using actual libp2p handlers, production Redis/media backends, ephemeral Redis-compatible state/media roots, `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true`, `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=true`, a reachable host multiaddr, and deterministic teardown. A small Sims adapter starts the fixture, injects its exact `MKNOON_RELAY_ADDRESSES` before central build preparation, invokes central Sims preparation and scenario execution separately, and stops the fixture in `finally`. Reuse the existing dispatcher with a dedicated campaign/evidence module, artifact validator, runner contract, proof binding, and discovery mapping; do not create another mobile harness or touch external/production relay state.
11. Run focused and exact preservation gates, then curated `1to1`, justified core and stable serial feature families, Android bindings/device proof, analyzer/format/diff. Do not run full `host-all` or iOS.
12. Refresh `graphify-arch` incrementally once after coherent app-owned implementation. Update this plan, index, and coverage report with receipts while leaving production activation, external share, remaining GAP-N01 lanes, wave `host-all`, and iOS open.

## Gate Cadence And Acceptance Commands

Independent Go modules may run alongside one focused Flutter invocation. Do not launch competing Flutter/Android builds against the same output directory.

```bash
# Baseline and first RED.
git status --short
git rev-parse HEAD
flutter test \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'TC-347-02 fresh prepared voice ambiguity then restart reuses one durable ciphertext'

# Focused Dart/SQL/domain/repository proofs after implementation.
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/migrations/111_direct_media_blob_custody_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/bridge/p2p_bridge_client_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/features/conversation/application/upload_media_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_media_reupload_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/domain/models/message_payload_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/conversation/integration/android_direct_media_blob_custody_campaign_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/account_migration/application/migration_database_schema_inventory_test.dart \
  test/features/account_migration/application/migration_file_manifest_builder_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  test/features/account_migration/application/account_migration_end_to_end_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  test/tool/sims/sims_proof_binding_registry_test.dart \
  test/tool/sims/sims_verification_test.dart

# Exact selector-false preservation promised by TC-347-08.
flutter test \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  --plain-name 'retry re-encrypts with a fresh key and persists updated metadata to the attachment row'

# Native/relay exact families; execute in separate jobs if desired.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_(DirectMediaEnvelopeExpiryCeiling|AckCustody)' \
  -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -tags integration ./... \
  -run '^TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace$' \
  -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -tags integration . \
  -run '^TestDirectMediaBlobCustodyDeviceFixtureContract$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge \
  -run 'MediaCustody|InboxAckCustodyMediaExpiryCeiling|InboxStoreMediaExpiryCeiling' \
  -count=1)

# Existing integration/contract rails.
bash scripts/test/relay_media_custody_contract_test.sh
bash scripts/test/direct_media_blob_custody_prebuilt_runner_contract_test.sh
bash scripts/test/reliability_simulation_discovery_contract_test.sh
bash scripts/test/sims_major_plan_contract_test.sh
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh 1to1

# Shared production surfaces changed by this plan.
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1

# Existing exported bridge implementation must be rebuilt into Android.
./scripts/ensure_go_android_bindings.sh
./scripts/verify_gomobile_bindings.sh android
bash scripts/test/go_binding_staleness_contract_test.sh

# Rediscover IDs, then replace these planning-snapshot values with the exact
# currently available physical Android and Android emulator IDs.
flutter devices --machine
adb devices -l
PLAN347_ANDROID_ID='21071FDF600CSC'
PLAN347_ANDROID_PEER_ID='emulator-5554'

# DB v111 proof plus every existing literal-current-version SQLCipher sentinel.
plan347_sqlcipher_proofs=(
  integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart
  integration_test/direct_notification_durability_sqlcipher_proof_test.dart
  integration_test/direct_reaction_inbox_custody_outbox_sqlcipher_proof_test.dart
  integration_test/group_exit_intents_sqlcipher_proof_test.dart
  integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart
  integration_test/group_self_removed_marker_sqlcipher_proof_test.dart
)
for proof_file in "${plan347_sqlcipher_proofs[@]}"; do
  flutter test "$proof_file" -d "$PLAN347_ANDROID_ID"
done

# Preserve the existing release-mode SQLCipher/plugin boundary.
ANDROID_SERIAL="$PLAN347_ANDROID_ID" ./android/gradlew -p android \
  :app:connectedReleaseAndroidTest --no-parallel \
  -PenableGroupExitReleaseDiagnosticsProof=true \
  -PdisableGoogleServicesForDisposableProof=true \
  -PandroidApplicationId=com.mknoon.app.pb266proof \
  -Ptarget="$PWD/integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart" \
  -Ptarget-platform=android-arm64

# The adapter starts/attests the disposable relay, injects its exact address
# before the central build, calls Sims prepare and run as two operations, and
# always tears the fixture down. It never invokes flutter build/drive itself.
RELIABILITY_MULTI_DEVICE_IDS="$PLAN347_ANDROID_ID,$PLAN347_ANDROID_PEER_ID" \
  dart run integration_test/scripts/run_direct_media_blob_custody_sims.dart \
  --mode major --scenario android.direct_media_blob_custody

# Hygiene and one post-implementation graph refresh.
flutter analyze
git diff --name-only --diff-filter=ACM -- '*.dart' | xargs dart format --output=none --set-exit-if-changed
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

The literal focused selectors added during implementation must also be run individually when diagnosing a failure. No fixed pass-count is an acceptance criterion. Do not run full `host-all`; run it once after the relevant GAP-N01 dependency wave and again at final rollout/release closure.

## Device / Relay Proof Profile

- Planning snapshot on 2026-08-08 found physical Pixel 6 `21071FDF600CSC` and Android emulator `emulator-5554`; these are examples, not hard-coded closure prerequisites. Rediscover immediately before execution and pin exact live IDs.
- Default TC-347-09 topology is one USB-connected physical Android sender plus one available Android emulator receiver. The existing Sims dispatcher and small scenario module own app setup, permissions, identities, navigation, send, sender process kill/restart, receive, file/hash/reopen assertion, ACK, and relay post-ACK assertion. No manual taps count.
- The test-only adapter starts a reachable tagged Go fixture before build preparation. The fixture uses actual libp2p handlers, production Redis/media backend code, ephemeral Redis-compatible state and media roots, `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true`, `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=true`, and a unique relay identity/address; it never contacts or mutates an external relay. The adapter proves both devices can reach the announced host address, injects it as `MKNOON_RELAY_ADDRESSES`, and tears down process/state in `finally`.
- Both devices install the same centrally attested `android.e2e.direct_media_custody` APK. Only that profile enables the client selector; unrelated `android.e2e.main` campaigns remain unchanged.
- The fixture proves production codecs/handlers/backends across a real process and two devices. It is not evidence for a deployed relay, Redis-server persistence/HA, or old production binary rollback.
- Plan 347 has no iOS-specific OS boundary. Do not run an iPhone/iOS simulator or use it as peer two. Unavailable Android versions are `N/A (target unavailable by project policy)`, not a blocker. If no Android pair is available, record only TC-347-09 as unavailable and retain the host/native evidence; do not substitute iOS.

## Risks And Blind Spots

- File and SQL operations cannot share one transaction. The safe publication order leaves only removable file-orphans before a row; a published row with a missing/mismatched artifact is fail-closed corruption.
- A relay can have accepted the body while the client lost the response. Exact same-ciphertext retry is the convergence mechanism; broad fallback would split identity.
- A strict receipt can age before envelope staging after long suspension. The expiry ceiling preserves truthfulness but can terminalize the attempt at the bound; automatic re-encryption is forbidden.
- The per-entry expiry field is additive JSON but changes protected Redis semantics. Rollback to an old binary while strict media is admitted is not proved here and therefore remains an activation prerequisite, not a code-closure claim.
- Sender ciphertext retention consumes private storage until v108 settlement/cleanup. Existing per-message/media limits and write-failure handling apply, but Plan 347 does not invent an aggregate local quota or evict active authority. Production quota/UX is an explicit WP-07 activation prerequisite; ENOSPC must fail closed before network and metrics expose only aggregate pending count/bytes.
- Incoming ACK may commit remotely before local row deletion. Exact same-source `already_acked` is the required restart convergence path.
- External share remains a real uncovered ordinary-direct sender lane. Excluding it avoids inventing unstable identity; it must be scheduled explicitly after Plan 347 rather than silently counted closed.
- Protected blobs remain single-relay, not replicated. Host loss, backup, HA, canary thresholds, and fleet rollout are operational boundaries.

## Execution Interpretation And Done Criteria

- [ ] TC-347-02 has a retained behavioral RED against the Plan 346 production-source baseline, GREEN after implementation, and one representative re-encryption/deletion mutation re-red.
- [ ] DB v111/v108 nullable bindings, one-way version floor, host migration, Android SQLCipher reopen/wrong-key/run-twice, and prior v108-v110 preservation are green without backfill.
- [ ] Fresh composer/voice publish the complete v111 generation before any LAN/relay request; exact retries only reopen it, work after original plaintext removal, and concurrent preparers adopt one winner without overwrite/deletion.
- [ ] A v110 attempt without v111—including partial legacy success—stays wholly legacy and retry never promotes it.
- [ ] Strict upload validates/persists the complete Plan 346 proof tuple and never falls back after strict selection.
- [ ] Every strict attachment commitment and v108 manifest hash/earliest expiry are exact and transaction-bound; pre-v111 rows stay legacy.
- [ ] Relay envelope expiry is never later than earliest blob expiry; exact duplicates preserve expiry; text/reaction omission remains compatible.
- [ ] Incoming parent/all attachments/v111 stage before all side effects; relay download commits attachment+source+ACK state atomically; source-less verified LAN adoption issues no delete/ACK and converges by expiry; restart/parent deletion are green.
- [ ] Lifecycle cleanup and account transfer preserve exact DB/file authority without exposing proof material on wire/logs.
- [ ] All three production activation controls remain false: the client selector and both relay admissions. Only the coordinator and strict download/ACK owner call strict bridge helpers; separate typed-schema owners are exact; external share/private/group/historical/pre-upgrade exclusions pass.
- [ ] Focused/preservation gates, curated `1to1`, justified core/feature families, Android bindings, analyzer/format/diff, and one incremental Graphify refresh pass. No per-plan full `host-all` runs.
- [ ] All seven current-schema SQLCipher proofs (including the connected release leg) and TC-347-09 pass on explicit rediscovered Android IDs when available. The fixture is locally created/attested/torn down, no external relay is mutated, no user taps occur, and no iOS command runs.
- [ ] Plan/index/coverage closure wording leaves external share, private/group/historical/fanout, WP-07 activation, wave-level full `host-all`, operations evidence, and consolidated iOS open.

## Handoff

- First RED: fresh voice producer -> ambiguous upload -> original-source removal -> process-recreated retry in the existing voice test; it uses only baseline types and observes exact ciphertext.
- Migration: DB v111 independent artifact/proof/ACK state plus nullable v108 manifest hash/earliest expiry; no historical promotion.
- Sender boundary: Plan 345 durably prepared ordinary direct composer/voice and their retry paths only. External share stays legacy pending durable pre-upload identity.
- Receiver boundary: one atomic parent/all-attachments/v111 commit before side effects; exact Plan 346 download and durable source-pinned ACK when a relay source exists; verified LAN-local bytes wait for expiry without legacy delete.
- Relay boundary: reuse Plan 346 media actions and Plan 344 protected inbox action; add only optional per-entry expiry ceiling semantics. No recipient capability action.
- Interface boundary: add one sibling media-only expiry-bounded inbox capability; do not widen the common text/reaction `AckOrExpiryInboxStore` contract or its fakes.
- Rollout boundary: default-off code proof only; the client selector and both relay admissions remain off in production. WP-07 owns authenticated non-push capability/cohort selection, aggregate local ciphertext quota/UX, and production mixed-version activation.
- Gate boundary: focused/affected gates now; full `host-all` at dependency-wave and final release closure only; Android pair now when available; iOS later.
- Release claim: Plan 347 closes only this prepared ordinary-direct client-adoption slice. It does not close all ordinary-direct blob senders, the media item, GAP-N01, or release eligibility.

## Reviewer Findings

Initial verdict: `needs-fixes`

| Finding | Disposition | Plan correction |
|---|---|---|
| The draft treated push-token capabilities as an existing general recipient capability registry. | Confirmed material defect. | Removed capability registration, relay unsupported-recipient behavior, and strict-to-legacy negotiation. Production activation is explicitly deferred to WP-07 and independent of push enrollment. |
| External share has no recoverable message identity before upload, so restart-safe adoption would require redesigning its producer. | Confirmed scope expansion. | Sender scope is prepared composer/voice plus exact retries; external share remains legacy and named open. |
| DB v111 duplicated keys/nonces and v108 duplicated the full canonical manifest/count. | Confirmed unnecessary duplication. | Existing attachment rows retain crypto; v111 stores artifact/proof/ACK state; v108 stores only manifest hash/earliest expiry and binds exact rows by incarnation. |
| A retry-only first RED would authorize unsafe strict promotion of a pre-upgrade attempt; multi-attachment preparation could mix strict and legacy generations. | Confirmed correctness defect. | First RED now begins at a fresh producer. Complete v111 publication precedes every network side effect; retry is reopen-only, and absent-v111/partial-legacy rows remain wholly legacy. |
| Incoming parent/attachments were split and LAN-local bytes have no relay source for an exact ACK. | Confirmed correctness defect. | Added one strict incoming transaction before side effects; relay download commits source+ACK state atomically, while verified LAN-local adoption suppresses legacy deletion and converges by expiry. |
| The draft proposed parallel SQLCipher/device harnesses and an unflagged shared APK. | Confirmed overengineering/invalid proof. | Reuse the direct-inbox SQLCipher file, existing dispatcher and Sims engine; add only a dedicated compile profile, small scenario/evidence adapter, and local strict-relay fixture required by this boundary. Run all seven current-schema proofs on one explicit Android. |
| The expiry ceiling might be avoidable through a longer blob TTL plus client preflight. | Refuted. | That alternative adds retention/capacity pressure, hard-codes relay lease policy in the client, and strands suspended sends because only the recipient may ACK. Retain one optional relay-authoritative ceiling; both protected and shadow rows obey it, while omission preserves text/reaction. |
| Widening the common inbox interface and allowing every typed owner to call strict media helpers would create needless churn/bypass risk. | Confirmed scope defect. | Add one sibling media-ceiling capability. Only coordinator and strict download/ACK owner may call strict media helpers; other layers exchange typed state. |
| Activation wording collapsed the existing inbox admission, media admission, and new client selector into an ambiguous pair. | Confirmed rollout-boundary defect. | Name all three default-off production controls. The disposable device fixture alone enables the two relay admissions, while its dedicated APK alone enables the client selector. |
| The cleanup guard omitted proof-expiry terminalization even though the state table permitted it. | Confirmed authority contradiction. | Cancellation and exact proof-expiry may publish cleanup only with verified v108 absence; a bound row reaches cleanup only through exact atomic v108 completion. |
| Several test paths/registrations/commands were non-literal, vacuous, or used unstable concurrency. | Confirmed plan-quality defect. | Corrected paths; added tagged Redis/bridge/app-drain proofs, exact account/composer/voice tests, pinned SQLCipher/release commands, serial feature family, and separate Sims build/run lifecycle. Only the migration and campaign host tests are new manual registrations. |
| Aggregate local ciphertext quota was implied but not designed. | Confirmed release-boundary issue, not Plan 347 code scope. | Active authority is never evicted and ENOSPC fails before network; metrics expose aggregate count/bytes. Aggregate quota/UX remains an explicit WP-07 activation prerequisite. |
| Per-plan full `host-all` or iOS was needed for closure. | Refuted by project policy and changed surfaces. | Use focused/curated plus justified core/feature families and the available Android pair; reserve full `host-all` for the dependency wave/final closure and iOS for the later platform wave. |

Final verdict: `ready`

The reviewed plan has one explicit causal RED, observable boundary outcomes, crash/restart and destructive-transition coverage, bounded sender eligibility, source-backed preservation sentinels, exact gate ownership, and an honest activation/release boundary. The final independent reliability and scope/gate rechecks both returned `ready`; no product decision blocks default-off implementation.

## Execution Progress

Planning/review only. No Plan 347 implementation, migration, generated binding, production flag, relay deployment, test execution, Graphify refresh, or release claim was performed in this planning turn.
