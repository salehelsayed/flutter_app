# 346 - GAP-N01 Relay Media Blob Non-Destructive ACK-or-Expiry Durability

Status: **IMPLEMENTED / PLAN-GREEN / AGGREGATE `1to1` GREEN / NOT STANDALONE RELEASE-ELIGIBLE** (`$tdd-plan` + `$tdd-review`, updated 2026-08-08)
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5 requirements 1, 3, and 6 plus A-01/A-02/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01
Classification: enabling relay/native primitive only; not standalone release-eligible and not closure of the GAP-N01 media-blob item
Closure tier: host-native relay/protocol/filesystem/process proof, curated aggregate `1to1`, and Android gomobile binding build; no full `host-all`, mobile-device, or iOS-device acceptance
Execution provenance: implementation was user-directed from active dirty Plan 345 work at HEAD `976c660ff`; there is no clean post-Plan-345 baseline or raw first-behavioral-RED receipt.

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-07 | Evidence Collector | PRD §5/§5.1; GAP-N01/WP-01 report; Plans 344/345; relay media store/handler/tests/metrics/bootstrap; Go node media selector; Go/Dart bridge; media upload/download/retry use cases; gates and local relay/process fixtures | Download is non-destructive and Dart sends legacy delete only after durable local commit, but the relay can overwrite a completed same-ID blob and capacity-prune an older unacknowledged blob. No response proves immutable blob custody. | Define the smallest protected filesystem/protocol primitive without adopting it in Plan 345's sender path. |
| 2026-08-07 | Planner | Same source plus v108 lifetime, ciphertext cleanup/re-encryption, mixed-relay behavior, sidecar recovery, and Android binding scripts | Keep the frozen media protocol; add an isolated strict store, exact encrypted-byte identity/proof, one proof-bearing relay, and no conversation adopter. Defer durable client artifact reuse and envelope/blob TTL coupling. | Draft causal test rows and bounded acceptance gates. |
| 2026-08-07 | Reviewer | Complete draft plus current relay/node/bridge source; Graphify review profile; independent core, protocol/domain, and boundary/reversibility audits | The first draft was not ready: an incorrect implementation could remain undownloadable, accept false duplicate proof after ACK, advance to another relay after an ambiguous commit, ACK the wrong relay, or lose committed state on restart while its tests passed. | Add strict download, literal outcomes, phase-aware selection, source-pinned ACK, commit-marker recovery, admission-off drain, cross-lane/path tests, behavioral metrics, and non-vacuous discovery. |
| 2026-08-07 | Arbiter | All reviewer findings rechecked against current source | Accepted the correctness findings. Removed protected `list` integration and the temporary Dart source-inventory test; kept one shell no-adopter guard. Rejected Redis/object storage, replication debt, DB work, a new protocol ID/export, device/iOS proof, and per-plan full `host-all`. | Execute only after Plan 345 commits cleanly and re-run the baseline/anchor check. |

## Problem And Evidence

- Plan 345 protects the fresh ordinary-direct encrypted chat envelope and attachment descriptors, not the separately uploaded ciphertext blob (`Test-Flight-Improv/345-gap-n01-fresh-ordinary-direct-media-voice-inbox-custody-tdd-plan.md:96,158,306,323`). An inbox envelope can therefore survive after its referenced blob has been replaced or evicted.
- `MediaStore.store` replaces a global same-ID entry and then calls destructive `prunePeerLocked`; the installed count/byte tests expect oldest-item deletion (`go-relay-server/media.go:137-193`; `go-relay-server/media_test.go:606-670`).
- `handleMediaUpload` renames new bytes over the final blob before metadata persistence and returns broad `OK`; metadata rename is file-synced but the directory is not (`go-relay-server/media.go:279-312,433-505`). `NewMediaStore` logs/ignores construction and sidecar failures instead of exposing a protected-store startup error (`:58-68,314-353`).
- Media requests and responses have no custody kind, encrypted-byte hash, exact store/ACK state, expiry proof, or typed error code (`go-relay-server/media.go:357-374`; `go-mknoon/node/media.go:19-44`).
- `Node.MediaUpload` stops at the first relay whose stream opens and sends the entire body before reading final confirmation (`go-mknoon/node/media.go:257-264,326-416`). Advancing to another relay after a lost final response could create two untracked owners.
- `Node.MediaDownload` can try another relay after `not found`, but accepts the first broad `OK`; a legacy same-ID blob can mask a later protected copy (`go-mknoon/node/media.go:419-486`). `Node.MediaDelete` chooses the first open relay and sends only ID (`:525-550`).
- The download result already carries the concrete source relay through Go and the bridge (`go-mknoon/node/media.go:104-116`; `go-mknoon/bridge/bridge.go:1653-1690`). The strict ACK can reuse that value without a new platform export.
- Dart already computes lowercase SHA-256 over encrypted bytes and records it as `MediaAttachment.contentHash` (`lib/features/conversation/application/upload_media_use_case.dart:581-597,797-814`). The native strict primitive must nevertheless hash the actual local file before an immediate duplicate can be trusted.
- Relay download does not delete. Dart sends legacy `media:delete` after durable local commit, never as proof that notification outcome completed, and no delete is sent after failed integrity/download (`go-relay-server/media.go:510-566`; `lib/features/conversation/application/download_media_use_case.dart:1423-1464`; `test/features/conversation/application/download_media_use_case_test.dart:1453-1528,4040-4103`).
- Current path components come directly from request `To` and `ID` (`go-relay-server/media.go:267-276,433-456`). A protected subtree is not isolated unless both strict inputs and legacy access to its reserved root are path-safe.
- The PRD does not define a separate media-blob protocol. This is a repository-derived prerequisite for making a custodied authenticated media event retrievable until recipient persistence ACK or expiry. It enables §5/A-02/A-03; it does not itself complete inbox-before-push ordering or end-to-end media custody.
- Plan 345's v108 row has no durable blob commitment, its lifetime can exceed a blob accepted earlier, and a failed retry may regenerate different ciphertext under the same blob ID after the temporary ciphertext is removed. Plan 346 therefore exposes no conversation adopter. A following GAP-N01 plan must preserve/reuse the exact artifact and couple/preflight blob expiry before transferring v108 envelope custody.
- Planned production/test/ops surfaces: `go-relay-server/main.go`, `media.go`, new `media_custody.go`, `metrics.go`, relay protocol/media/custody/rollout/process tests, `go-mknoon/node/media.go`, `go-mknoon/bridge/bridge.go`, focused node/bridge/integration tests, `lib/core/bridge/p2p_bridge_client.dart`, its test, `scripts/run_test_gates.sh`, one custody shell contract, relay README/dashboard, and rebuilt Android bindings. No Flutter DB, conversation sender/retry, feature production, or iOS file is in scope.

## Graph Grounding Snapshot

- TDD query: `python3 graphify-arch/tdd_context.py query "Plan 346 GAP-N01 direct media blob MediaStore.store prunePeerLocked handleMediaUpload handleMediaDelete mediaMeta media_test non-destructive capacity ACK expiry durability" --profile tdd --budget 700`.
- Review query: `python3 graphify-arch/tdd_context.py query "Plan 346 counterexamples upload_custody_v1 ack_custody_v1 DirectMediaBlobCustody MediaStore Node.MediaUpload v108 blob expiry retry ciphertext" --profile review --budget 800`.
- Fingerprint / freshness: `fb4bdce90e0c343b`; stale against Plan 345's concurrent uncommitted files. Graph anchors were used only as a shortlist and all material decisions were verified in current source.
- Anchors: `MediaStore` -> `go-relay-server/media.go:49`; `handleMediaDelete()` -> `:568`; `MediaMeta` -> `go-mknoon/node/media.go:39`; `TestMediaStoreSurvivesRestart` -> `go-relay-server/media_test.go:150`; incomplete replacement -> `:182`.
- Reuse rule: execution must query/re-pin these anchors after Plan 345 lands; do not refresh Graphify during this planning-only turn or while the other session owns the dirty graph.

## Scope Contract And Guard

In scope:

- Keep `/mknoon/media/1.0.0`. Add `upload_custody_v1` and `ack_custody_v1`; make existing `download` strict only when all custody fields are present. Legacy requests omit the fields and retain legacy behavior. Do not add protected `list` behavior.
- Strict identity is `(custodyKind=direct_media_blob_v1, custodyContract=ack_or_expiry_v1, canonical recipient peer ID, blob ID, lowercase SHA-256 of encrypted bytes, ciphertext size, opaque MIME)`. The authenticated download/ACK peer must equal the recipient. No sender identity is stored.
- Use path-safe strict inputs: canonical libp2p recipient ID; blob ID matching a bounded single-segment grammar such as `[A-Za-z0-9_-]{1,128}`; exactly 64 lowercase hex hash characters; positive size within `maxMediaSize`; bounded printable MIME with no control/NUL. Validate resolved containment under the intended root before any file creation. Apply equivalent segment/reserved-root rejection to legacy filesystem actions so `..`, separators, absolute paths, or the reserved custody directory cannot reach the strict subtree.
- Store strict state under `<media-root>/.custody-v1/` with non-`.json` sidecars ignored by the legacy loader. A final strict sidecar is the commit marker. Both temporary files are fsynced/closed; rename the final blob and fsync its directory; rename the sidecar last and fsync the directory again; publish the index and return proof only afterward. Newly created directory entries are also made durable.
- Open/reconcile the strict store synchronously before registering `MediaProtocol`. The constructor returns an error. Clean only recognizable temp or blob-before-marker artifacts; fail startup while preserving unreadable/corrupt final sidecars, marker-without-blob, cross-lane same-ID state, containment violations, or cleanup failures. Legacy corrupt-sidecar tolerance remains unchanged.
- Exact pending duplicate is checked before capacity and can return its original proof before `READY`; the native client must hash/stat its local file before trusting that result. Any tuple difference is terminal conflict and cannot touch the original. An ACKed tombstone returns terminal `already_acked`, never a custody-accepting duplicate.
- Protected pending byte/count capacity is independent of legacy capacity and reuses the existing configured limits; the two lanes may consume their summed allowance. Pending plus ACK tombstones occupy protected identity slots until original expiry, bounding replay metadata; ACK releases blob bytes only. A distinct full write returns `rejected_full` without eviction. Capacity, duplicate/conflict, expiry normalization, and commit reservation linearize under one store lock.
- Add `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED`, default false. Admission-off rejects only new strict stores before `READY`; strict download, exact ACK, expiry, restart reconciliation, and cleanup of existing rows remain active. Enabling is outside this plan.
- Strict download requires the exact tuple, serves only protected pending state, returns exact proof before bytes, verifies streamed bytes natively, and records the concrete source relay. Proof-less legacy `OK`, wrong proof, tombstone, and expired state cannot satisfy strict download. Legacy download/list never exposes protected state.
- Exact ACK targets only the configured relay peer that supplied strict download proof. It sends the exact tuple, never falls through to another peer, and may retry only that peer's sibling addresses. `acked` and `already_acked` with exact proof are success; generic/mutated proof is not.
- ACK transition under the same lock: durably replace pending marker with exact ACK tombstone and fsync; remove pending authority from lookup; unlink blob and sync; only then return `acked`. Cleanup failure retains the tombstone, suppresses download/re-upload, returns typed retryable cleanup state, and is retried on startup/access/sweep. Do not expire the tombstone while leftover bytes remain.
- Enforce `now >= expiresAtMs` synchronously on strict upload/download/ACK and during sweep/restart. Expiry never refreshes an existing proof. Once physical cleanup succeeds, pending/tombstone state is removed; a later upload is a new admission rather than `duplicate`.
- Add strict Go node/bridge primitives behind the existing exported `MediaUpload`, `MediaDownload`, and `MediaDelete` JSON commands, plus optional Dart bridge parameters/results. No new gomobile-exported function and no feature caller.
- Add behavioral fixed-cardinality metrics, a default-off/relay-first/roll-forward note, one dedicated non-vacuous gate, hermetic process/mixed-relay tests, and Android binding rebuild/verification.

### Exact Wire And Selector Outcomes

Success proofs use `status=OK` and exact `id`, `custodyKind`, `custodyContract`, `contentHash`, `size`, `mime`, and original `expiresAtMs`. Upload also has `storeStatus`; ACK has `ackStatus`. Native/bridge results attach `custodyRelayPeerId`; that field is not trusted from the relay payload. For a new upload, `status=READY` is only body-transfer authorization and is never custody proof; the relay reserves the ID/count/bytes under lock before `READY`, and releases that reservation on incomplete transfer.

| Operation/outcome | Required typed result | Custody/selector meaning |
|---|---|---|
| Upload new pending | `storeStatus=stored` + exact proof | Custody accepted; stop after this one relay. |
| Upload exact pending | `storeStatus=duplicate` + original exact proof | Custody accepted; no body and no expiry refresh. |
| Upload while admission off | `status=ERROR`, `errorCode=MEDIA_CUSTODY_ADMISSION_DISABLED`, `storeStatus=disabled` | Explicit pre-body non-commit; next relay is allowed. |
| Distinct upload at protected cap | `status=ERROR`, `errorCode=MEDIA_CUSTODY_FULL`, `storeStatus=rejected_full` | Explicit pre-body non-commit; next relay is allowed. |
| Old relay / proof-less strict response | Native-normalized `MEDIA_CUSTODY_UNSUPPORTED` | Next relay is allowed only before body transfer; never fall back to legacy upload/download success. |
| Identity collision, invalid tuple/auth, local/relay hash mismatch | `MEDIA_CUSTODY_IDENTITY_CONFLICT`, `MEDIA_CUSTODY_INELIGIBLE`, `MEDIA_CUSTODY_NOT_AUTHORIZED`, or `MEDIA_CUSTODY_HASH_MISMATCH` | Terminal; routing around it could split identity or hide a caller defect. |
| Upload against exact ACK tombstone | `status=ERROR`, `errorCode=MEDIA_CUSTODY_ALREADY_ACKED`, `storeStatus=already_acked` | Terminal and never accepted as blob custody. |
| Strict download pending | Exact proof followed by exactly `size` bytes whose hash matches | Accept and record that relay as ACK source. Explicit not-found/unsupported may try the next relay; auth/conflict is terminal. |
| ACK first completion | `ackStatus=acked` + exact proof after unlink/directory sync | ACK complete on the named source relay. |
| Repeated exact ACK | `ackStatus=already_acked` + original exact proof | Idempotent success on the same relay. |
| ACK cleanup incomplete | `MEDIA_CUSTODY_CLEANUP_PENDING` with no success proof | Retry the same source relay; tombstone still blocks authority. |
| ACK absent/expired | `MEDIA_CUSTODY_NOT_FOUND` with no success proof | No cross-relay ACK. Expiry remains the removal fallback. |

Phase rule: connect/open/request/pre-`READY` transport failure and explicit typed non-commit can try another configured relay. Once `READY` is accepted or any body byte may have been sent, a write failure, dropped response, or malformed/missing final proof is `MEDIA_CUSTODY_COMMIT_INDETERMINATE`. Make one bounded exact duplicate probe against the same relay peer (sibling addresses allowed); if it cannot recover the original proof, return the indeterminate result with that peer ID. Never advance to another relay. “No replication” means no intentional fanout and no cross-peer advance after ambiguous commit.

Must preserve:

- Frozen protocol ID and valid legacy action/status/payload behavior -> `go-relay-server/protocol_contract_test.go::TestProtocolIDContract_Frozen` and `TestMediaCustodyAdditiveWireContract`.
- Valid legacy same-ID incomplete replacement, count/byte pruning, download/redownload/delete, expiry, group ACL/repeated download/no auto-delete, profile actions, sender omission, and legacy `from` sidecars -> existing focused tests in `go-relay-server/media_test.go` and `profile_test.go`.
- Invalid traversal-shaped legacy input may newly fail closed; no installed-client compatibility is claimed for unsafe path components.
- Strict and legacy IDs cannot coexist in an upgraded store. Strict admission over legacy ID conflicts; a new-binary legacy upload over a protected reservation returns error without false success/mutation. If an old binary creates a collision during unsupported rollback, the next upgraded startup preserves both artifacts and fails closed.
- Legacy ID-only delete aimed at a protected reservation returns compatible `OK`/no-op; it cannot remove the protected bytes or tombstone. Legacy lookup/list cannot serve protected state.
- Existing Dart commit-before-delete and no-delete-on-failure behavior. Plan 346 does not replace legacy delete in a feature caller.

Hard `Do not`:

- Do not begin execution before Plan 345 commits and the shared worktree is clean; do not edit its DB v110/v108 staging, send/retry/bootstrap, SQLCipher, coverage, Graphify, or active gate changes in this planning turn.
- Do not add Redis/object storage, DB v111, a Flutter migration, replica debt, a scheduler/worker, resumable chunks, distributed/shared-disk locking, a new libp2p protocol ID, or a new gomobile export.
- Do not adopt strict custody in ordinary/private/group/post/avatar sends, change v108 retirement, infer eligibility from empty `AllowedPeers`, or claim blob/envelope TTL alignment.
- Do not add all-relay replication, concurrent writers to one data directory, production activation/deployment, external credentials, mobile-device automation, or iOS work.

Deferred / accepted difference:

- Exact-ciphertext retry persistence, v108/blob commitment and expiry coupling, feature adoption, real Android two-peer blob-plus-envelope recovery, and removal of the no-adopter guard -> next bounded GAP-N01 plan.
- Private/disappearing media, group per-member ACK, posts/avatars, historical blob promotion/backfill, and per-device fanout -> their existing GAP-N01 owners.
- Live capacity tuning, filesystem mount durability/backup/restore, host-loss HA, admission enablement, old-binary rollback artifact, canary thresholds/provenance, and deployment -> WP-07/operations. An old binary cannot drain admitted protected rows; roll forward to an upgraded binary.
- iOS binding/runtime parity -> consolidated GAP-N12/WP-07 phase after non-iOS gaps are code-complete. No iOS result is needed for this host/native primitive.

Dependencies:

- Plan 344 supplies the existing exact ACK-or-expiry vocabulary and rollout pattern. Plan 345 supplies the fresh ordinary-media envelope/descriptors and encrypted content hash, and must land first.
- Existing single-writer relay filesystem ownership remains the boundary. The process test reopens one volume sequentially; it does not authorize simultaneous processes.

## Test Contract

`HEAD` means the clean committed post-Plan-345 baseline captured before execution. Every first behavioral RED must compile against that baseline by using raw action strings/JSON maps and existing framing seams; it must not import future production constants/types.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Representative mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-346-01 | Additive wire table, strict validation, and default-off admission/drain | `go-relay-server/direct_media_blob_custody_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyActionProofAndAdmissionContract`; `go-relay-server/protocol_contract_test.go::TestMediaCustodyAdditiveWireContract`; `go-relay-server/media_custody_rollout_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains` | Host Go / raw framed libp2p requests, production stores, exact JSON-key assertions | HEAD compiles and returns unknown action/no proof -> GREEN exact outcomes above; admission defaults off, store rejects before `READY`, existing strict state still downloads/ACKs/expires | Accept broad `OK`, omit a discriminator, enable by default, emit dynamic error text only, or alter protocol ID -> red | Closure prefix AUTO under `1to1`; protocol exact; dedicated gate contract |
| TC-346-02 | Tuple/path identity, protected sender privacy, and both-direction legacy/protected collision isolation | `go-relay-server/direct_media_blob_custody_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyIdentityPathAndCrossLaneIsolation` | Host Go / real temp filesystem and framed handlers | HEAD overwrites same ID and accepts path components -> GREEN exact pending duplicate is stable; every tuple/path difference rejects before filesystem mutation; protected sidecar has no sender; both collision directions preserve original | Compare ID only, persist remote peer, allow `..`/separator/reserved root, let legacy upload/delete shadow protected, or promote legacy -> red | Closure prefix plus exact legacy preservation selector |
| TC-346-03 | Protected capacity is non-evicting and race-linearized; exact pending duplicate wins before cap; tombstones keep bounded identity slots | `go-relay-server/direct_media_blob_custody_test.go::{TestRelayNotificationClosure_DirectMediaBlobCustodyRejectsCapacityWithoutEviction,TestRelayNotificationClosure_DirectMediaBlobCustodyConcurrentAdmission}` | Host Go / real filesystem, tiny constructor limits, deterministic barriers, race detector | HEAD prunes oldest and reports success -> GREEN distinct full preserves all authority; exact duplicate succeeds; last-slot and same-ID races have one stable winner | Call `prunePeerLocked`, check cap before duplicate/expiry, free tombstone identity early, or split reservation/commit locks -> red | Closure prefix; focused `-race` |
| TC-346-04 | Sidecar-as-commit-marker response durability and fail-closed sequential-process recovery | `go-relay-server/direct_media_blob_custody_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyAtomicCommitRecovery`; `go-relay-server/direct_media_blob_custody_process_integration_test.go::TestDirectMediaBlobCustodySurvivesRelayProcessHandoff` | Host Go / real filesystem, narrow file-op failpoints, helper subprocess, same directory reopened sequentially | HEAD renames bytes before metadata and cannot report protected startup failure -> GREEN temp/blob-before-marker states reconcile; returned/ambiguous committed proof reloads with original expiry; corrupt/impossible committed states preserve files and fail startup | Publish before final dir sync, treat blob alone as committed, ignore corrupt marker, register handler before reconcile, or use process memory -> red | Untagged exact + tagged `-list` and non-skipped PASS in dedicated gate |
| TC-346-05 | Strict known-ID download serves exact protected bytes repeatedly before ACK only, skips proof-less/wrong relay responses, and rejects intruder/tombstone/expiry | `go-relay-server/direct_media_blob_custody_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyStrictDownloadLifecycle` | Host Go / real handler/filesystem, recipient and intruder peers, deterministic clock | HEAD strict fields are ignored and broad legacy state can win -> GREEN only exact pending proof+bytes succeeds; second pre-ACK download matches; no access after ACK/expiry | Read legacy map, accept missing/wrong hash proof, delete on first download, serve tombstoned bytes, or authorize wrong peer -> red | Closure prefix; native selector companion in TC-346-08 |
| TC-346-06 | ACK/tombstone/expiry are exact, idempotent, cleanup-safe, and linearized with store/download | `go-relay-server/direct_media_blob_custody_test.go::{TestRelayNotificationClosure_DirectMediaBlobCustodyExactAckOrExpiry,TestRelayNotificationClosure_DirectMediaBlobCustodyConcurrentStoreDownloadAckConverges}` | Host Go / real handler/filesystem, deterministic before/at/after-expiry clock, barriers and failpoints | HEAD ID-only delete removes immediately and has no tombstone -> GREEN exact ACK marker persists before retirement; repeat ACK recovers; wrong peer/hash and legacy delete preserve; late upload cannot publish; cleanup failure suppresses state past expiry until cleanup | Return ACK before sync/unlink, return duplicate from ACK tombstone, expire marker before leftover, rely only on ticker, or authorize ID alone -> red | Closure prefix and focused `-race` |
| TC-346-07 | Valid legacy/group/profile/privacy behavior survives; legacy rollback actions cannot see/prune strict subtree and upgraded reopen recovers it | Existing focused `media_test.go`/`profile_test.go`; `direct_media_blob_custody_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyLegacyRollbackPreservation` | Host Go / production legacy handlers plus strict real filesystem | `GREEN sentinel` for valid legacy behavior -> same results; upgraded -> legacy handlers/cleanup -> upgraded strict duplicate/download/ACK remains valid | Use `.json` strict marker, merge strict into list, let legacy prune traverse strict index, or change valid profile/group behavior -> red | Exact selector then full relay module |
| TC-346-08 | Native upload is phase-aware, strict download selects exact proof, and ACK is pinned to the actual source relay | `go-mknoon/node/media_custody_test.go::{TestMediaCustodyUploadPhaseAwareRelaySelection,TestMediaCustodyStrictDownloadSelectsExactProof,TestMediaCustodyAckPinsSourceRelayAndRequiresExactProof}`; `go-mknoon/integration/media_custody_mixed_relay_test.go::TestMediaCustodyMixedRelayMatrix` | Host Go / production selector, deterministic loopback old/disabled/full/conflict/drop-proof/new relays, real ciphertext file | HEAD accepts first broad response and ACKs first open relay -> GREEN safe pre-body fallback, no legacy fallback, local+relay hash verification, same-peer ambiguous recovery, exact source ACK, and no post-success fanout | Advance after dropped final proof, accept a different local file on immediate duplicate, accept proof-less strict download, ACK another relay, or accept generic/mutated proof -> red | Separate node discovery/PASS plus tagged integration discovery/PASS in dedicated gate |
| TC-346-09 | Existing Go/Dart bridge commands carry optional upload/download/ACK custody fields and exact result/source; legacy payloads stay byte-compatible; no feature caller adopts | `go-mknoon/bridge/media_custody_test.go::TestDispatchMediaCustodyContract`; `test/core/bridge/p2p_bridge_client_test.dart::{media custody upload carries explicit exact contract,media custody download carries exact contract and source relay,media custody ack carries hash and source relay,legacy media commands omit custody fields}`; shell no-adopter assertion | Host Go + Dart + shell / production bridge dispatcher and fake Bridge | HEAD cannot map exact outcomes -> GREEN optional fields/results round-trip; defaults are unchanged; custody tokens occur only in allowed relay/node/bridge/test/docs files | Drop source/hash/expiry, synthesize proof in Dart, make fields unconditional, add feature caller, or add a gomobile export -> red | Separate bridge discovery/PASS; Dart AUTO under core; shell contract |
| TC-346-10 | Runtime metrics, docs, and gate registration are behavioral, fixed-cardinality, and non-vacuous | `go-relay-server/media_custody_rollout_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyMetrics`; `scripts/test/relay_media_custody_contract_test.sh`; `scripts/run_test_gates.sh::run_media_custody_go_gate` | Host Go + shell / Prometheus `testutil`, restart fixture, README/dashboard/gate source | HEAD has no metrics/gate -> GREEN relay counter/gauge deltas cover stored/duplicate/full/conflict/acked/already-acked/expired/cleanup plus reconstructed pending blob/byte and tombstone counts; TC-346-08 observes native `indeterminate_after_body`; no peer/blob/hash labels | Register but never increment, use unbounded labels, omit ambiguity event, omit tagged discovery, hide in Plan 344 gate, or register only once -> red | Closure prefix + shell; dedicated gate called by `1to1` and `all` |
| TC-346-11 | Android artifact includes revised existing bridge implementation without a new platform API | `scripts/ensure_go_android_bindings.sh`; `scripts/verify_gomobile_bindings.sh android`; `scripts/test/go_binding_staleness_contract_test.sh` | Host Android toolchain / production gomobile build and artifact verifier | HEAD artifact lacks strict behavior -> GREEN rebuild/verify/staleness exit 0 and exported API surface is unchanged | Skip rebuild, add export, or leave stale artifact -> red | Exact commands; no device target |

### Test Notes

- TC-346-01 is the first behavioral RED. The later protocol-constant test may be a compile RED, but it cannot substitute for the raw framed unknown-action RED.
- TC-346-02 tests strict-first and legacy-first collisions. A deliberately constructed both-lane on-disk collision is preserved and rejects upgraded startup; it is not auto-promoted, overwritten, or silently quarantined.
- TC-346-04 commit matrix: temp-only; durable blob without marker; valid pending pair; ACK marker plus leftover blob; clean ACK marker; expired clean state; malformed/unreadable final marker; marker without blob; both-lane ID collision; removal/sync failure. Only recognizable pre-marker artifacts may be cleaned without operator action.
- TC-346-05 adds strict optional fields to existing `download`; protected rows are never merged into legacy `list` or broad download.
- TC-346-06 races exact re-upload and ACK at the lock decision boundary and applies a stale-reservation mutation. Correct same-ID reservation makes a contender wait/re-evaluate to `duplicate`, `conflict`, or `already_acked` without streaming a second body; no stale commit token may publish after the tombstone. At/after expiry, old state is normalized under the lock before duplicate/cap/ACK decisions.
- TC-346-08 commit-then-drop case: relay A durably stores, loses final proof, relay B sees zero strict attempts, same-file probe/retry against A returns original `duplicate`/expiry, and a changed local file/hash is terminal conflict. The plan permits one proof-bearing relay, not intentional replication.
- TC-346-10 relay metrics use bounded `outcome` values only. Native ambiguity is a fixed flow outcome, not a peer/hash-labeled Prometheus series.

## Implementation Steps

1. Wait for Plan 345's clean commit. Record `git status --short` and `git rev-parse HEAD`; confirm 346 is unique; re-run the compact TDD query; re-pin Plan 345, bridge, media, and gate anchors. Stop if Plan 345 added blob custody or changed exact-artifact/v108 dependencies enough to invalidate this contract.
2. Add TC-346-01's raw framed behavioral RED and run the valid legacy preservation selector separately. Then add remaining relay REDs before production edits; do not let a compile failure stand in for the first causal RED.
3. Add the narrow strict store in `go-relay-server/media_custody.go`: validation/containment, isolated codec, injected clock/file-op seam, single lock/reservations, duplicate/conflict/capacity, sidecar-last commit marker, fail-closed startup reconciliation, ACK tombstone, on-access expiry, and fixed typed outcomes. Change media construction/main startup only enough to return and handle strict-store errors.
4. Route explicit `upload_custody_v1`, strict-field `download`, and `ack_custody_v1`; gate only new upload admission. Keep legacy list/storage indexes separate, reserve the strict root/IDs from legacy mutation, and preserve valid legacy/group/profile behavior.
5. Add native outcome types and phase-aware upload, strict download, and source-pinned ACK in `go-mknoon/node/media.go`. Reuse the current relay selector and existing bridge exports. Hash/stat the local upload before the first request; do not add a hashing service, replica ledger, or retry worker.
6. Add optional fields/results to the existing Go/Dart bridge commands. The shell contract rejects custody-token references from `lib/features/**`; no temporary Dart runtime inventory test is added.
7. Add behavioral metrics, default-off/roll-forward documentation, dashboard panels, `run_media_custody_go_gate`, tagged process/mixed-relay discovery, and shell registration. Keep Plan 344's inbox gate separate.
8. Run focused GREEN and representative identity/capacity/commit/download/ACK/ambiguity mutation re-reds; then full affected Go packages, exact preservation, `1to1`, justified `core-host-all`, Android binding build/verify, analyzer, formatting, and diff hygiene. Do not run per-plan full `host-all`, `feature-host-all`, a phone campaign, or iOS.
9. Refresh Graphify once after coherent implementation. Update this plan, index, and coverage report with actual receipts while stating that client adoption/TTL coupling remains open.

## Risks And Blind Spots

- Current retries can re-encrypt the same ID after deleting the temporary ciphertext. The no-adopter guard prevents unsafe use; the next plan must durably reuse exact bytes/key/nonce/hash before v108 handoff.
- Blob expiry begins at blob acceptance while envelope acceptance may occur later. No end-to-end retrievability claim exists until the next plan couples or preflights those clocks.
- An old relay binary cannot understand protected rows. Isolation makes normal rollback actions non-destructive, but old-binary availability after admission is unsupported; restore the upgraded binary to drain.
- Two artifact renames are not a filesystem transaction. Sidecar-last commit marking plus synchronous reconciliation defines which pre-proof states are discardable and which committed/impossible states fail closed.
- ACK cleanup can fail after the tombstone commits. The marker remains authoritative and blocks reads/re-upload even past nominal expiry until cleanup succeeds; metrics expose this operator condition.
- Pending plus ACK tombstones consume bounded identity slots until original expiry. Production values and disk alert thresholds must be validated before the later admission-on rollout.
- Logical limits do not prevent underlying disk exhaustion. A failed fsync/rename returns no proof; disk provisioning, backup, and HA are rollout evidence, not an object-storage project here.
- The single-writer mount is assumed. Concurrent processes/shared storage are explicitly unsupported.

## Gate Cadence

- Per-plan: focused relay/node/bridge/Dart/shell tests; race/process/mixed-relay proofs; exact legacy/group/profile sentinels; full `go-relay-server`; affected `go-mknoon` node/bridge; dedicated gate; curated `1to1`; `core-host-all` because shared Dart bridge code changes; Android binding ensure/verify; hygiene.
- `feature-host-all` is not required because no feature production file adopts the primitive. If execution touches one, stop and re-review scope and cadence.
- Do not run full `host-all` for Plan 346. Run it once after the GAP-N01/N02/N03 dependency wave and once at final rollout/release closure, paired with the complete relay/native/process family.
- Tagged process/mixed-relay tests and the shell contract run exactly now and remain registered under `all`; registration does not create a per-plan full-`all` obligation.

## Acceptance Gates

```bash
# Prerequisite: Plan 345 committed and no output from status.
git status --short
git rev-parse HEAD

# First causal RED: raw strings/maps compile on HEAD; expect non-zero for
# unknown action/no exact proof. The valid legacy selector must remain green.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_DirectMediaBlobCustodyActionProofAndAdmissionContract$' \
  -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run 'TestMediaUploadSameIDIncompleteReplacementKeepsExistingBlob|TestPeerPruning|TestPeerByteCapPruning|TestGroupMediaUploadDownload|TestGroupMediaNoAutoDelete|TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia|TestRedownloadSucceeds|TestDeleteAfterDownloadRemovesBlob|TestBackwardCompat|TestMediaSidecarAtRestOmitsSender|TestMediaStoreLoadsLegacySidecarWithFromField|TestProfileUploadDownload|TestProfileDelete' \
  -count=1)

# Focused relay GREEN/race and exact tagged process discovery/PASS.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run 'TestRelayNotificationClosure_DirectMediaBlobCustody|TestMediaCustodyAdditiveWireContract' \
  -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race . \
  -run '^TestRelayNotificationClosure_DirectMediaBlobCustody' -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -tags integration ./... \
  -list '^TestDirectMediaBlobCustodySurvivesRelayProcessHandoff$' | \
  rg -x 'TestDirectMediaBlobCustodySurvivesRelayProcessHandoff')
bash -o pipefail -c "cd go-relay-server && GOTOOLCHAIN=go1.25.0 \
  go test -tags integration ./... \
    -run '^TestDirectMediaBlobCustodySurvivesRelayProcessHandoff$' -count=1 -v | \
  rg '^--- PASS: TestDirectMediaBlobCustodySurvivesRelayProcessHandoff \\('"
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)

# Native tests are separately discoverable and non-vacuous.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -list '^TestMediaCustody(UploadPhaseAwareRelaySelection|StrictDownloadSelectsExactProof|AckPinsSourceRelayAndRequiresExactProof)$' | \
  rg '^TestMediaCustody' | awk 'END { exit NR == 3 ? 0 : 1 }')
bash -o pipefail -c "cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestMediaCustody(UploadPhaseAwareRelaySelection|StrictDownloadSelectsExactProof|AckPinsSourceRelayAndRequiresExactProof)$' \
  -count=1 -v | rg '^--- PASS: TestMediaCustody' | awk 'END { exit NR == 3 ? 0 : 1 }'"
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -list '^TestDispatchMediaCustodyContract$' | rg -x 'TestDispatchMediaCustodyContract')
bash -o pipefail -c "cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^TestDispatchMediaCustodyContract$' -count=1 -v | \
  rg '^--- PASS: TestDispatchMediaCustodyContract \\('"
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration \
  -list '^TestMediaCustodyMixedRelayMatrix$' | rg -x 'TestMediaCustodyMixedRelayMatrix')
bash -o pipefail -c "cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration \
  -run '^TestMediaCustodyMixedRelayMatrix$' -count=1 -v | \
  rg '^--- PASS: TestMediaCustodyMixedRelayMatrix \\('"
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1)

# Dart optional-field compatibility and installed commit-before-delete sentinels.
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'media custody upload carries explicit exact contract'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'media custody download carries exact contract and source relay'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'media custody ack carries hash and source relay'
flutter test test/core/bridge/p2p_bridge_client_test.dart \
  --plain-name 'legacy media commands omit custody fields'
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'ack delete fires only after decrypt and durable commit'
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'media:delete failure does not affect done status'
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'no media:delete on failed download'

# Docs/metrics/no-adopter/discovery and proportionate curated families.
bash scripts/test/relay_media_custody_contract_test.sh
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2

# Android artifact only; no phone, simulator, or iOS harness.
bash scripts/ensure_go_android_bindings.sh
./scripts/verify_gomobile_bindings.sh android
bash scripts/test/go_binding_staleness_contract_test.sh

# Hygiene for every planned source/test file.
bash -n scripts/run_test_gates.sh scripts/test/relay_media_custody_contract_test.sh
jq empty go-relay-server/grafana-relay-dashboard.json
gofmt -l \
  go-relay-server/main.go \
  go-relay-server/media.go \
  go-relay-server/media_custody.go \
  go-relay-server/metrics.go \
  go-relay-server/media_test.go \
  go-relay-server/protocol_contract_test.go \
  go-relay-server/direct_media_blob_custody_test.go \
  go-relay-server/direct_media_blob_custody_process_integration_test.go \
  go-relay-server/media_custody_rollout_test.go \
  go-mknoon/node/media.go \
  go-mknoon/node/media_custody_test.go \
  go-mknoon/bridge/bridge.go \
  go-mknoon/bridge/media_custody_test.go \
  go-mknoon/integration/media_custody_mixed_relay_test.go | \
  awk 'NF { bad=1; print } END { exit bad }'
dart format --output=none --set-exit-if-changed \
  lib/core/bridge/p2p_bridge_client.dart \
  test/core/bridge/p2p_bridge_client_test.dart
flutter analyze
git diff --check

# Execution only, once after the coherent code change.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Device/Relay Proof Profile

- Profile: real temporary filesystem + framed relay handlers + deterministic loopback old/new relays + sequential helper-process reopen + Android gomobile build.
- It proves protected file/marker/tombstone recovery, exact action/proof parsing, phase-aware single-relay selection, strict download source, source-pinned ACK, and Android artifact inclusion.
- No device discovery is required. `FLUTTER_DEVICE_ID`, two-phone topology, Android emulator, iPhone, and iOS simulator are N/A for this primitive.
- Go 1.25 and Android SDK/NDK are required. Missing phone/OS versions cannot block closure under project policy.
- Every tagged test must be listed and emit a non-skipped PASS. No external relay, credentials, Redis, or production volume is used.
- A real Android two-peer blob-plus-envelope campaign belongs to the later adoption/wave closure. iOS runtime/binding proof remains consolidated under GAP-N12/WP-07.

## Execution Interpretation And Done Criteria

- Planned first RED: raw strict upload receives unknown action/no exact proof on a clean post-345 baseline while the adjacent valid legacy selector remains green. Execution instead began by explicit user direction from dirty Plan 345 work at HEAD `976c660ff`, so no raw first-RED receipt is claimed.
- Representative mutation receipts must cover at least: ID-only equality, duplicate-after-cap ordering, proof before directory sync, broad strict download, post-body cross-peer fallback, wrong source ACK, and tombstone-as-duplicate.
- The missing clean baseline is an execution-provenance limitation, not evidence that Plan 345's dirty changes belong to Plan 346. Focused GREEN receipts below establish the implemented primitive but cannot retroactively establish the planned RED chronology.
- Missing Go 1.25 or Android SDK/NDK blocks those host/build legs. Unavailable phones/iOS targets are N/A, not evidence gaps.
- Any feature adoption, DB/v108 change, durable ciphertext queue, protected list, historical promotion, replication, distributed filesystem, new platform export, device/iOS harness, or production activation is scope drift and requires a new/re-reviewed plan.

- [x] Every row has a named causal test, mutation, fixture, and non-vacuous gate.
- [ ] First behavioral RED compiles against baseline; focused GREEN and representative mutation re-reds are recorded.
- [x] Exact identity/path/cross-lane, non-destructive capacity, commit recovery, strict download, tombstone/expiry, and phase-aware relay tests pass.
- [x] Valid legacy/group/profile/privacy behavior stays green; unsafe path input fails closed.
- [x] Admission defaults off and drains existing protected state; no feature caller opts in.
- [x] Dedicated gate is mechanically present under `1to1` and `all`; all tagged parents are discovered and non-skipped.
- [x] Full affected Go modules, justified `core-host-all`, and Android binding checks pass; no per-plan full `host-all`/feature/device/iOS claim.
- [x] Aggregate `1to1` passes: 2,968 Flutter tests plus relay notification/toolchain, ACK-custody, media-custody process, bridge, mixed-relay, deterministic gomobile stamp, and no-adopter tails are green; wrapper exit 0.
- [x] Metrics change behaviorally, docs/JSON/shell are valid, analyzer/format/diff hygiene pass.
- [x] Coverage language after implementation says relay/native primitive only and keeps client adoption/TTL coupling open.

## Reviewer Findings

| Finding | Disposition in reviewed plan |
|---|---|
| Protected store could pass while no protected download path worked | Added TC-346-05 strict exact download and native proof selection; removed unnecessary protected list. |
| ACK tombstone could answer `duplicate` and falsely prove missing bytes | Added literal pending/ACKed state outcomes; `already_acked` is terminal for upload and success only for repeated exact ACK. |
| Cross-lane and protected privacy claims cited only legacy tests | Added causal both-direction collision, reserved-root, no-sender sidecar, legacy delete/prune, rollback, and fail-closed both-lane tests. |
| ACK could still use first configured relay and ID only | Added exact source-pinned native ACK test and no-cross-peer rule. |
| Protected non-evicting capacity was exposed without rollout control | Added a separate default-off admission flag whose off state still drains/reconciles existing rows. |
| Wire outcomes and selector meanings were conceptual | Added the exact outcome table and strict parser/mutation requirements. |
| First RED could fail to compile | Required raw strings/maps against existing framing types for the behavioral RED. |
| Transport fallback could create two owners after lost final proof | Made selection phase-aware; added commit/drop-proof, same-peer recovery, and untouched-next-relay assertions. |
| Pair commit/startup could silently ignore committed corruption | Defined sidecar-last marker, directory barriers, synchronous error-returning reconciliation, and a process state matrix. |
| Expiry/tombstone cleanup relied on the periodic ticker | Added under-lock on-access expiry and cleanup-failure persistence across expiry. |
| Metrics/discovery/format checks could pass vacuously | Added behavioral `testutil` deltas, separate package discovery/PASS checks, and every planned Go file to hygiene. |
| Temporary product inventory and protected list expanded the slice | Removed both; the dedicated shell contract enforces the no-feature-adopter boundary. |

## Arbiter Decision (Planning-Time)

Planning verdict after revision: **READY FOR EXECUTION ON THE DECLARED POST-PLAN-345 CLEAN BASELINE**. That baseline was not obtained; later implementation proceeded by explicit user direction from the dirty Plan 345 tree, as recorded in Execution Progress.

- Accepted all correctness blockers and the default-off admission guard because they protect the exact durability claim.
- Selected a sidecar-last commit marker and fail-closed protected-store startup; legacy forgiving load behavior remains isolated and unchanged.
- Selected strict optional fields on existing `download` rather than a new action/protocol/export, and source-pinned ACK rather than fanout.
- Retained one relay with phase-aware selection. All-relay replication and replica debt remain rejected as unnecessary for the PRD slice.
- Retained the narrow file-op seam, tombstone, one process proof, one mixed-relay proof, and Android artifact build because they exercise real claimed boundaries.
- Removed protected list, a temporary Dart inventory test, feature-family sweep, DB/client adoption, devices, iOS, and production activation to avoid over-engineering.
- Plan 346 remains a primitive: its implementation must not mark GAP-N01 media-blob custody closed. Plan 347 owns durable exact-ciphertext client reuse, adoption of the strict upload/download/source-pinned ACK APIs, persistence of the relay proof tuple, and v108 blob-commitment/expiry coupling before envelope custody transfer.

## Handoff

- First RED: the TC-346-01 raw framed command above; expected behavioral failure is unknown action/no exact proof, not compile failure.
- Preservation: the adjacent valid legacy selector must pass on the same baseline.
- Contract: 11 rows covering relay wire/storage/recovery/download/ACK, native selection, bridge compatibility, metrics/gates, and Android artifact.
- Migration: none. A DB/v108 blob commitment is explicitly deferred.
- Device boundary: host-native plus Android binding build; no phone/simulator/iOS leg.
- Aggregate owner: full `host-all` and full relay/native/process family once after the dependency wave and once at release closure.
- Execution caveat: the intended clean Plan 345 baseline and raw first RED were not captured; do not infer them from the later GREEN receipts.
- Remaining blockers: client exact-ciphertext reuse, feature adoption, persisted relay proof, and envelope/blob TTL alignment remain open by design under Plan 347; aggregate shared-gate closure is complete.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-07 | planning | plan only | `$tdd-plan` drafted; `$tdd-review` revisions applied | Graph/source grounded; no production tests or implementation run at that point | Plan 345 was active in the shared worktree | superseded by the user-directed execution record below |
| 2026-08-08 | execution provenance | Plan 346 production and test surfaces in the shared tree | starting HEAD `976c660ff`; Plan 345 still active and dirty | implementation was explicitly user-directed without a clean post-345 checkpoint | no raw first behavioral RED or clean-baseline receipt exists | preserve this limitation in closure claims |
| 2026-08-08 | custody-specific closure | relay, native node, bridge, Dart bridge client, process/mixed-relay, and dedicated Plan 346 gate surfaces | focused relay/native/bridge/Dart/process/gate suites PASS, including focused race coverage and tagged non-skipped process proof; full `go-relay-server` PASS; full affected native rerun PASS (`node` 330.576s, `bridge` 147.578s) | exact tuple/proof, protected capacity, restart recovery, strict download/source ACK, legacy compatibility, default-off admission, and no-adopter boundaries are green | this proves only the relay/native primitive; exact ciphertext reuse and blob/envelope TTL coupling remain unimplemented | keep admission off and GAP-N01 open |
| 2026-08-08 | initial aggregate and hygiene pass | curated `1to1`; justified `core-host-all`; Android bindings; analyzer, changed-file hygiene, and Graphify | Plan 346 `1to1` subgates PASS; the first aggregate `1to1` attempt stalled in the then-dirty Plan 345 `external_share_media_ux_test.dart`, reproduced in isolation. `core-host-all` PASS (402 Flutter paths / 3,190 tests plus both Android manifest contracts); Android binding ensure/verify/staleness PASS; `flutter analyze` PASS; Go/Dart format, shell syntax, dashboard JSON, and `git diff --check` PASS; Graphify incremental refresh PASS (69,094 nodes / 102,015 edges; overlay 1,557 files / 15,133 tests / 1,181 targets) | the historical stall established no Plan 346-causal failure; all other declared Plan 346 host/build/hygiene legs were green | shared aggregate rerun remained open at that point | rerun after Plan 345 closure |
| 2026-08-08 | final aggregate closure | curated `1to1` with all registered non-Flutter tails | `./scripts/run_test_gates.sh 1to1` -> 2,968 Flutter tests PASS; relay notification/toolchain PASS; ACK-custody process/bridge/mixed-version and deterministic gomobile-stamp checks PASS; media-custody process/bridge/mixed-relay/no-adopter checks PASS; wrapper exit 0. Log: `build/plan346-1to1-aggregate-final.log` | the former Plan 345 share-media stall is resolved and the complete shared gate is green on the Plan 345 commit plus Plan 346 tree | Plan 346 is plan-green only as the default-off relay/native primitive; no admission or client-adoption claim | retain admission off and hand exact-ciphertext/v108 adoption to Plan 347 |
| 2026-08-08 | final Graphify closure | incremental architecture refresh plus affected-context query | 25 changed / 3,098 unchanged / 0 deleted; 69,148 nodes / 102,080 edges; 3,123 manifest rows; overlay 1,557 files / 15,137 tests / 1,181 production targets; affected log `build/plan346-graphify-affected-final.log` | graph SHA-256 `009093649f46fe635e91abde367e4af7252305f1dcd73aa56f2a0810ad5e3b70`; manifest SHA-256 `c82c552625baafc05d4354a65325976faa0839f79d9091a42fd7f5e60d0fdef2`; overlay SHA-256 `48bb5baea71f55bbb81a5feca9ef3d7867fafb2514b0d11e6e1b6d932acc9bcb`; all manifest hashes match current source; no Plan 347 or temporary path leaked | none | audit exact Plan 346 staging and commit |
| 2026-08-08 | isolation-safe changeset | exact Plan 346 staging and commit boundary | 25 paths; sorted path-set SHA-256 `de4ebe6c07a05d72f76e46e8dd137972d301d4bf36c63269e9388d7541bf4053`; every staged blob byte-identical to working source; staged diff-check clean | no Plan 347 artifact exists in the candidate; implementation and closure evidence are committed together in this changeset | none | create Plan 347 separately after this commit |
