# 269 - Group Media End-To-End Reliability

Status: implementation and allowed closure complete — TC-269-19 PASS;
TC-269-20 physical proof FAIL and user-directed bypass after one capped run
(2026-07-23)
Type: Bug
Spec: free-text intent — diagnose and eliminate every confirmed sender,
persistence, relay-authorization, and receiver-recovery defect that makes
ordinary group image, video, or voice delivery unreliable
Classification: implemented with one unresolved device-proof exception
Closure tier: device — accepted with explicit TC-269-20 exception

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-22 10:02 CEST | Evidence Collector | Pixel `21071FDF600CSC` application logs; sender SQL/flow events; relay upload responses; current group/member state | The reproduced JPEG and MP4 never reached group publication. Both relay uploads returned `ok:true`, then exact completion attempted a SQL `NULL` write into `download_retry_count`; the five-minute retrier uploaded them again | trace the counter, exact-CAS, ACL, lease, and receiver paths in current source |
| 2026-07-22 10:13 CEST | Evidence Collector | `group_conversation_wired.dart`; `media_attachment.dart`; migrations 042/089; `retry_incomplete_group_uploads_use_case.dart`; media DB helpers/repositories; upload outcome | SQLite defaults nullable Dart counters to zero, strict in-memory comparison rejects `null` versus `0`, successful upload results omit both counters, and completion restores only the upload counter. No schema change is needed | inspect every sender sibling and failure projection |
| 2026-07-22 10:19 CEST | Counterexample / receiver audit | group ACL builder/member device model; Dart/Go media request serialization; relay authorization; incoming handler/listener; download use case; lifecycle retrier; auto-download policy; iOS critical-task bridge | Confirmed account-ID/transport-ID ACL mismatch, empty-ACL direct downgrade, unstable foreground lease IDs, `.heif` rejection, duplicate-enrichment starvation, absent durable group download recovery/policy enforcement, and an unprotected iOS receive transfer; receiver authorization convergence remained a hypothesis pending relay-store verification | define causal host, repository, relay, and OS-boundary proofs |
| 2026-07-22 10:24 CEST | Planner + two independent contract workers | focused tests; `GROUP_TESTS`; host-family gates; relay tests; reliability discovery/manifest; live Flutter/ADB/Xcode device matrix | Consolidate sender and receiver work under one 20-row contract. Required default device topology is USB Pixel plus Android emulator; iPhone 11 is a separate iOS-specific proof. iPhone 13 is excluded | write implementation ordering, registration, and literal gates |
| 2026-07-22 10:29 CEST | Planner | complete contract, scope guard, mutation targets, gate cadence, dirty-tree baseline | Plan 269 is the next free top-level number. Existing Docker and `info.plist` edits are unrelated and must be preserved | run the blocking sufficiency checklist and hand off the first RED |
| 2026-07-22 10:36 CEST | Blocking sufficiency audit | all 20 rows; exact preservation names; SQL/relay/native/device boundaries; registration and cadence; `sufficiency-checklist.md` | Every behavior has an honest RED/sentinel/device proof, mutation, fixture, literal gate, and registration. Real SQLCipher/relay/iOS claims close only at their real boundaries; no checklist blocker remains | hand off execution-ready artifact and offer `$tdd-review` |
| 2026-07-22 10:58 CEST | Independent `$tdd-review` + critical synthesis | current sender/receiver source, raw bridge callers, dedupe exits, route/lifecycle wiring, SQL helpers, relay ACL store, Swift critical-task owner, Sims executor/build profiles, gates | Pre-revision verdict `plan-fixes-required`: receiver-only authorization convergence was refuted; share/avatar/route bypasses, non-atomic failure writes, recovery starvation/readiness, native expiry, and proof-runner contracts were under-specified. The source-backed deltas are incorporated below | rerun all five lenses and execute only the revised contract |
| 2026-07-22 13:08 CEST | Critical fixlist audit + three independent verifiers | `269-review-fixlist.md`; completion field ownership; gate arrays; all group-route constructors/dedupe callers; Android/iOS lifecycle harnesses; relay delete semantics | Accepted the unmasked `created_at`/`thumbnail_hash` corruption, missing registrations/routes/dedupe coverage, and proof-boundary tightening with corrections. Rejected blanket full-row freezing, group relay delete-ack, legacy-ACL attribution, volatile line-count gates, mandatory natural iOS expiry, and unavailable-hardware blocker language | execute in four RED-to-GREEN waves using only the revised source-backed contract |

## TDD Review Result

- Final verdict after revise-in-place: `ready`.
- Plan classification: implementation-ready Bug; core sender counter/ID/ACL
  and durable receiver-recovery direction `confirmed`. The narrower claim that
  receiver-only retries can make an already stored relay ACL authorize a peer
  is `refuted` and has been removed.
- Disposition: `execute` the revised causal contract.
- Five-lens rerun after both reviews: L1 evidence truth `clear`; L2 test causality `clear`; L3
  bypass/scope safety `clear`; L4 gate integrity `clear`; L5 boundary/state
  transitions `clear`.
- Blind-spot hits corrected: B-2 share/avatar/route/raw-call bypasses; B-3
  authorization-convergence evidence; B-4 terminal-on-first-failure, duplicate
  no-op, and ceremonial Sims proofs; B-5 completion-field ownership, atomic
  receiver failure, deletion races, lease timing, paging, and re-entry; B-7
  network/native fallback; B-8
  real relay, SQLCipher, and XCUITest boundaries; B-9 direct/private/integrity
  preservation; B-10 separated Android and iOS proof. B-1 is N/A because no
  schema/wire change is allowed; B-6 is covered by the durable query, cursor,
  and authoritative row transitions.
- The later `269-review-fixlist.md` was treated as adversarial input rather than
  applied mechanically. Its high-value findings are incorporated with an
  explicit upload/local field-ownership matrix, exact gate membership,
  invocation enumeration, and real restart proof. Unsafe or false proposals
  remain excluded: group downloads must not delete a relay blob needed by
  other members, the receiver cannot label a generic denial as a legacy ACL,
  and unavailable physical hardware is N/A under project policy rather than a
  closure blocker.

## Problem And Evidence

- Behavior to improve: a member must be able to send an ordinary image, video,
  or voice message to a group once and have every authorized active member
  receive, decrypt, persist, and render it without reopening the conversation
  or waiting for repeated five-minute uploads.
- Impact: the Pixel reproduced a complete sender-side failure for both JPEG and
  MP4. The UI appeared to send, the relay accepted the encrypted blobs, but no
  group message was published. The durable rows remained `upload_pending`, so
  `PendingMessageRetrier.defaultPeriodicRetryInterval` at
  `lib/core/services/pending_message_retrier.dart:34` re-uploaded the same
  media every five minutes. Independent source defects could then deny or
  strand the receiver even after sender completion is repaired.
- Confirmed incident root cause: ordinary attachments are constructed without
  retry counters at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:2278-2292`
  (voice at `:5105-5118`). `MediaAttachment.toMap()` omits nullable counters at
  `lib/features/conversation/domain/models/media_attachment.dart:185-202`,
  while migrations 042 and 089 define both columns `NOT NULL DEFAULT 0`.
  Reload therefore changes `null` to `0`; `sameExactGroupRetryAttachment` at
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart:914-937`
  compares them raw and foreground exits at
  `group_conversation_wired.dart:2418-2423` before publication.
- Confirmed retry/completion root cause: `UploadMediaSucceeded` is built without
  local retry authority at
  `lib/features/conversation/application/upload_media_use_case.dart:785-804`.
  Incomplete-group recovery restores only `uploadRetryCount` at
  `retry_incomplete_group_uploads_use_case.dart:1062-1075`; foreground ordinary
  and voice completion do the same at
  `group_conversation_wired.dart:2655-2734,5379-5442`. The exact DB completion
  maps an absent authority key to SQL `NULL` at
  `lib/core/database/helpers/media_attachments_db_helpers.dart:184-205,286-297`.
  Its outer retry catch at `retry_incomplete_group_uploads_use_case.dart:869-874`
  only logs, leaving an endlessly eligible row.
- Confirmed completion-authority defect unmasked by the counter fix:
  `_groupUploadAttachmentAuthorityFields` includes `created_at`, both retry
  counters, and `thumbnail_hash`, and `dbCompleteGroupUploadRetry` rewrites
  every non-identity field from the completed map at
  `media_attachments_db_helpers.dart:184-205,286-297`. The upload result stamps
  a new `createdAt` and has no thumbnail hash at
  `upload_media_use_case.dart:785-804`; foreground/retry builders currently
  base completion on that result. Once the `NULL` counter failure is removed,
  the same write would silently replace the persisted creation time and clear
  any local thumbnail hash. The correction must preserve those locally owned
  fields without freezing legitimate upload-owned outputs such as measured
  size, canonical MIME, durable path, hash, or encryption metadata.
- Confirmed lease root cause: the ordinary composer claims optimistic UUIDs at
  `group_conversation_wired.dart:2778-2799`, then durable preparation generates
  different UUIDs at `:2265-2292`; the actual persisted/uploaded blobs are not
  protected from the periodic retrier. Voice already allocates and reuses one
  ID at `:5027-5032,5091` and is the preservation pattern.
- Confirmed authorization defects: `group_media_allowed_peers.dart:3-14` emits
  account `GroupMember.peerId`, although the model distinguishes active device
  `transportPeerId` at `group_member.dart:74-101,385-415`. The relay authorizes
  the authenticated remote transport ID exactly at
  `go-relay-server/media.go:510-534`. An empty non-null ACL is also omitted by
  `p2p_bridge_client.dart:1104-1113`; Go serialization uses `omitempty`, and
  relay group mode is selected by non-empty length. Sending `[]` would therefore
  become a direct upload addressed to the group ID. The safe contract is to
  reject an empty group ACL before key generation, encryption, or transport;
  `allowedPeers == null` remains the direct-chat contract.
- Confirmed ACL bypasses: external share/forward builds `allowedPeers` directly
  from `member.peerId` at
  `lib/features/share/application/share_batch_delivery_coordinator.dart:1366-1371`,
  so a helper-only fix would leave a production group-media sender broken.
  Group-info/contact-picker avatar refreshes call raw `callP2PMediaUpload`
  through `group_avatar_storage.dart:84-136`; that raw path does not reject an
  empty ACL, and `group_info_wired.dart:1795-1798` resurrects an account-ID
  fallback when the member list is empty.
- Confirmed format defect: `_mimeFromPath` supports `.heic` but not `.heif` at
  `group_conversation_wired.dart:7294-7311`, so a valid HEIF image becomes
  `application/octet-stream` and is rejected before upload.
- Confirmed receiver defects: duplicate replay enriches missing attachments at
  `handle_incoming_group_message_use_case.dart:148-190,1310-1369` but returns
  `null`, while `GroupMessageListener` starts auto-download only for a non-null
  result at `group_message_listener.dart:1171-1195,1313-1319`.
- Confirmed receiver-state defect: ordinary group failures update status and
  retry count through two swallowed writes at
  `download_media_use_case.dart:730-819,1075-1107`. The later generic
  preserving save inserts a missing row at
  `media_attachments_db_helpers.dart:2074-2091`; a delete-for-me race can
  therefore resurrect an attachment, and a DB failure can split status from
  its counter. Success already has an owner-aware, deletion-journal-protected
  CAS at `media_attachments_db_helpers.dart:2530-2597`.
- Confirmed durability/policy defects: group listener download is untracked
  fire-and-forget and accepts only exact `pending` rows at
  `group_message_listener.dart:1967-2029`. The screen fallback runs only while
  the group is mounted/open at
  `group_conversation_wired.dart:1912-2036` and calls `downloadMedia` directly,
  so route-open/live refresh can bypass a future shared coordinator. There is
  no owner/parent-qualified durable query or process-wide retry for interrupted
  `downloading` and under-budget `failed` group rows. A fixed limited query
  would also starve eligible rows behind older policy-denied rows unless it
  pages past them. Unlike direct chat at
  `chat_message_listener.dart:221-260`, the group listener never consults the
  shared `MediaAutoDownloadDecider` immediately before transfer.
- Confirmed iOS boundary gap: existing `bgBegin`/`bgEnd` support is exposed by
  `lib/core/bridge/bridge.dart:781,820` and implemented in
  `ios/Runner/GoBridge.swift`; foreground group send defines its helper at
  `group_conversation_wired.dart:627-650` and wraps ordinary, manual-retry, and
  voice media at `:2851/:3163`, `:3383/:3418`, and `:5158/:5346`. Incoming
  group media has no critical
  task around a background transfer, so suspension can leave the durable row
  without a tracked completion. Native expiration independently ends its local
  task at `GoBridge.swift:235-241`, while a later Dart `bgEnd` reconstructs and
  blindly ends the same raw ID at `:260-273`; exact-once ownership therefore
  also needs a native live-task registry, deterministic unit seam, and iOS
  device proof.
- Existing coverage: the ordinary pre-persist/finalize and voice durable-ID
  widget tests cover happy-path structure but use in-memory repositories that
  preserve nullable counters instead of applying SQL defaults. Existing relay
  tests `TestGroupMediaUploadDownload`, `TestGroupMediaUnauthorizedPeer`, and
  `TestBackwardCompat` preserve exact authorization but do not construct ACLs
  from Flutter member/device rows. Existing download tests preserve not-found,
  authorization-denial, integrity, and private lifecycle outcomes but do not
  prove one atomic ordinary-group failure transition or deletion-race safety.
- Missing coverage: no current test crosses save/reload SQL defaults before the
  strict foreground leaf; preserves both counters, creation time, and thumbnail
  authority through completion while admitting upload-owned changes; proves a
  persistence exception consumes the existing bounded budget; owns the actual
  durable foreground IDs; builds relay ACLs from active device transport IDs;
  closes share/avatar ACL bypasses; rejects empty group ACLs before caller-side
  effects; atomically projects receiver failure; pages beyond denied rows;
  restarts enriched/interrupted group downloads through every automatic entry;
  applies group auto-download policy; balances normal versus expired iOS task
  ownership; or proves a fresh cross-device JPEG/MP4/voice round trip against a
  real relay and the same reopened SQLCipher role databases.
- Refuted findings: the iPhone receiver, current group membership, and group
  transport were not causal for the captured failure because the Pixel never
  published the group message. Both media relay uploads returned `ok:true`, so
  a transient relay-inbox retrieval timeout was not causal. The fresh group had
  two members and the sender node was online. The relay must not be weakened to
  accept account IDs or unauthorized transports.
- Refuted receiver mechanism: relay ACL metadata is stored with the upload and
  checked unchanged at download (`go-relay-server/media.go:137-151,522-534`).
  Sender publication follows successful upload/completion. A receiver-only
  retry cannot make an already denied blob authorize that receiver without a
  new sender repair protocol, which this plan intentionally does not add;
  `not authorized` remains immediately terminal.
- Unresolved findings: the captured run did not get far enough to exercise the
  account-ID/transport-ID ACL mismatch, receiver policy, or iOS suspension.
  Their defective mechanisms are source-confirmed, but linkage to that exact
  run is unresolved until TC-269-19/20. No further production hypothesis may
  be promoted without a causal RED or device artifact.
- Regression anchor: strict retry-leaf/CAS work entered in commit
  `1bb3c1c95792686cba69bed39ca9a583a311ea2a` on 2026-07-21. The plan preserves
  its exact authority checks and normalizes only DB-default-equivalent local
  counters.
- Affected production, test, gate, and harness files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `lib/features/groups/application/group_media_allowed_peers.dart`,
  `lib/features/groups/application/group_avatar_storage.dart`,
  `lib/features/groups/presentation/screens/group_info_wired.dart`,
  `lib/features/groups/presentation/screens/contact_picker_wired.dart`,
  `lib/features/groups/presentation/screens/group_list_wired.dart`,
  `lib/features/groups/presentation/screens/create_group_picker_wired.dart`,
  `lib/features/orbit/presentation/screens/orbit_wired.dart`,
  `lib/features/feed/presentation/screens/feed_wired.dart`,
  `lib/features/share/application/share_batch_delivery_coordinator.dart`,
  `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`,
  a new `retry_incomplete_group_downloads_use_case.dart`,
  `lib/features/groups/application/handle_incoming_group_message_use_case.dart`,
  `lib/features/groups/application/group_message_listener.dart`,
  caller-compatibility coverage for
  `drain_group_offline_inbox_use_case.dart` and
  `group_pending_key_repair_service.dart`,
  `lib/core/media/upload_media_outcome.dart`,
  `lib/features/conversation/application/upload_media_use_case.dart`,
  `lib/features/conversation/application/download_media_use_case.dart`,
  media attachment repository/DB helpers and interfaces, `lib/main.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`,
  `lib/core/services/pending_message_retrier.dart`, focused tests named below,
  `ios/Runner/GoBridge.swift`, `ios/RunnerTests/GoBridgeCriticalTaskTests.swift`,
  `ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift`,
  `integration_test/support/ios_xctestrun_relocator.dart` and its test,
  `scripts/run_test_gates.sh`, new
  `scripts/test/group_media_reliability_group_gate_registration_contract_test.sh`,
  reliability discovery/selection scripts,
  `tool/sims/critical_features.json`, and a dedicated two-role device harness.
  Shared native-registry impact is preservation-only for unchanged callers in
  `conversation_wired.dart`, `feed_wired.dart`,
  `share_batch_delivery_coordinator.dart`, and `handle_app_paused.dart`. Go
  production behavior is preservation-only.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `4b0b0be9a6cd02f8`;
  `stale:ios/Flutter/flutter_export_environment.sh`. The stale generated Xcode
  environment file is outside every planned behavior; load-bearing conclusions
  were verified in current Dart, SQL, Go, script, and test source.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "group media reliability sameExactGroupRetryAttachment dbCompleteGroupUploadRetry groupMediaAllowedPeersForMembers MediaUploadInFlightTracker group_message_listener downloadMedia group_conversation_wired_test GROUP_TESTS classify_path" --profile tdd --budget 700`
  returned `confidence=anchored`; no broad refinement was required.
- Review query / profile:
  `python3 graphify-arch/tdd_context.py query "counterexamples to Plan 269 group media reliability sameExactGroupRetryAttachment groupMediaAllowedPeersForMembers empty allowedPeers duplicateEnriched recoverable group downloads callBgBegin GROUP_TESTS reliability runner" --profile review --budget 800`
  returned `confidence=anchored` on the same fingerprint. Targeted source
  verification then found the share/avatar/route raw callers, failure-write
  split, and Sims/native boundary details not represented as graph anchors.
- Fixlist review query / profile:
  `python3 graphify-arch/tdd_context.py query "dbCompleteGroupUploadRetry _groupUploadAttachmentAuthorityFields UploadMediaSucceeded createdAt thumbnailHash GroupConversationWired orbit_wired feed_wired handleIncomingGroupMessage dedupeBy content GROUP_TESTS" --profile review --budget 800`
  returned `confidence=anchored` on the same fingerprint and surfaced the DB
  authority-field list, upload outcome, and group gate. Targeted source
  enumeration was still required for UI constructors, raw post/avatar callers,
  Android no-op behavior, and the XCUITest selector helper.
- Anchors: `sameExactGroupRetryAttachment` ->
  `retry_incomplete_group_uploads_use_case.dart:914`; `GROUP_TESTS` ->
  `scripts/run_test_gates.sh:348`; `classify_path` ->
  `scripts/check_reliability_simulation_discovery.sh:124`.
- Surfaced proof/gate files: retry use-case tests, group repositories,
  `group_conversation_wired_test.dart`, and the curated group gate array.
- Graph gaps requiring source search: optimistic/durable UUID divergence,
  nullable DB completion fields, receiver duplicate outcome, direct/group
  policy asymmetry, native critical-task bridge, Go `omitempty`/relay group-mode
  behavior, and live device topology. Targeted current-source inspection closed
  those gaps.
- Reuse rule: these anchors may be handed to review/execution; all conclusions
  still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Normalize the two local retry counters at the exact group authority boundary:
  SQL-default-equivalent `null` and `0` compare equal, while status, path, hash,
  owner, attachment identity, and every other exact-CAS field remain strict.
- Initialize new local group upload rows with both counters at zero and preserve
  both persisted counters through foreground ordinary, foreground voice, retry
  success, secure repository completion, and DB fallback completion.
- Apply one explicit completion field-ownership matrix at every foreground,
  retry, secure-repository, and fallback boundary. Identity/owner stay exact;
  locally owned `created_at`, `thumbnail_hash`, `upload_retry_count`, and
  `download_retry_count` come from the exact expected row. Completion may take
  canonical MIME, measured size/media type/dimensions/duration/waveform,
  durable local path, `done` status, content hash, and encryption metadata from
  the upload result. Do not blanket-freeze the full row or allow an upload
  timestamp/null thumbnail to overwrite local authority.
- Project a completion-persistence exception, or a false completion result
  followed by an unchanged exact pending row, as an explicit
  `consumerBoundary/boundedRetryable` failure through the existing upload
  budget. Retain the durable source until one completion lands, then clean it
  exactly once. A false result caused by genuinely changed authority remains a
  lost CAS and is not mutated. Do not invent a new status or retry loop.
- Allocate each ordinary attachment ID once before optimistic display and thread
  it through durable copy, row, lease, upload, retry, publish, and cleanup.
- Build group media ACLs from unique active device `transportPeerId`s, excluding
  revoked/blank entries and using account-ID legacy fallback only when no
  explicit device roster exists. Apply the helper consistently to foreground,
  voice, retry, external share/forward, group-info/contact-picker avatar, and
  the final send-time equality requalification. The fanout suite is a
  composer-path proof, not a separate production ACL construction site.
- Fail an explicit empty group ACL at ordinary/voice caller preflight before
  composer source removal, durable copy, optimistic parent/attachment save,
  bridge/keygen/encryption/upload, while retaining the shared upload-leaf guard
  against a roster change after preflight. Raw group-avatar upload rejects
  empty before file access, and group info has no account-ID empty-member
  fallback. Declare the exact shared code `EMPTY_GROUP_MEDIA_ACL` in
  `upload_media_outcome.dart`: the shared leaf returns
  `UploadMediaFailed` with validation stage, terminal disposition, and
  `errorCode: EMPTY_GROUP_MEDIA_ACL`; composer preflight projects the same code, and the
  nullable avatar lane emits that code before returning `null`. Preserve
  `allowedPeers == null` as direct mode; do not widen the avatar return API.
- Accept `.heif` as canonical `image/heic` at the composer boundary while
  retaining existing HEIC/video/audio validation.
- Preserve relay `not authorized` and `not found` as immediate terminal states
  that do not consume the bounded budget. For genuinely transient ordinary
  group failures, add one owner/message/expected-status CAS that atomically
  updates status, retry count, and optional path, and refuses a missing parent,
  missing row, or active group deletion journal. Integrity quarantine uses the
  same no-resurrection authority.
- Add `handleIncomingGroupMessageDetailed` returning
  `IncomingGroupMessageDetailedOutcome.delivered(message)`,
  `.duplicateEnriched(canonicalMessage, persistedAttachmentIds)`, or
  `.ignored`. `delivered` preserves every current non-null result, including a
  reconciled self echo; the existing `handleIncomingGroupMessage` wrapper
  delegates and maps exactly as today. Duplicate enrichment exists only for a
  non-empty set of attachment IDs actually persisted. All five dedupe exits are
  explicit: the four stable-ID branches may enrich; content-only dedupe stays
  ignored with zero attachment writes/recovery because its heuristic identity
  is too weak to authorize media attachment. Only the listener consumes the
  detailed outcome. Direct offline-drain and key-repair callers keep the
  nullable wrapper and rely on the later durable recovery sweep.
- Add one shared group-download coordinator/use case with a durable,
  owner/parent-qualified query for incoming ordinary group rows in
  `pending|downloading|failed` below the budget. Page by `(created_at,id)` with
  separate bounded scan and transfer limits so denied rows cannot starve later
  eligible rows. Trigger it on new/enriched delivery, automatic route-open/live
  refresh through every `GroupConversationWired` invocation under `lib/**`,
  resume after first group-inbox drain, usable-node network recovery, and periodic
  online passes; coalesce overlap through existing download single-flight/CAS.
  Explicit user retry/private-open paths remain separate.
- Consult the same preference-backed `MediaAutoDownloadDecider` immediately
  before listener or recovery transfer, using discussion or announcement kind.
  A denied row remains byte-for-byte pending.
- When the receiver is not resumed, own one injected iOS critical task around
  the tracked eligible transfer batch. A Swift registry atomically owns granted
  IDs so exactly one terminal path ends each task: normal Dart `finally` or the
  native expiration callback; a late duplicate `bgEnd` is a no-op. Refusal,
  expiration, interruption, or exception must leave authoritative durable
  `done` or bounded-retryable state, never an orphaned `downloading` row.
- Android `bgBegin`/`bgEnd` are hard no-ops at
  `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:176-178`; an Android
  receive therefore exercises the supported refusal/no-task branch by
  construction. TC-269-19 owns durable process-death recovery, while TC-269-17
  and TC-269-20 own the native/iOS task boundary.
- Add a focused two-role reliability harness and required Android real-relay
  proof using the centrally prepared `android.e2e.group_media_269` artifact, fresh
  disposable identities, structured Sims evidence, and the same reopened
  SQLCipher role DBs; add a separate deterministic XCUITest-controlled iOS
  suspension proof.

Must preserve:

- Direct media passes `allowedPeers == null`, advertises opaque direct MIME, and
  keeps its current retry/private rules -> TC-269-09/11/18.
- Relay authorization remains exact against authenticated transport IDs;
  unauthorized and removed devices remain denied -> TC-269-08/18/19.
- Relay `not authorized`, `not found`, exhausted retry, and integrity mismatch
  remain truthful terminal states -> TC-269-11.
- Existing incoming group private/view-once/disappearing media remains explicit
  user-only and is excluded from automatic recovery -> TC-269-13/14/15.
- Announcement reader/admin authorization, removed-member exact guards, and
  Plan 263 membership-phase ordering remain unchanged -> TC-269-05/08/13.
- Voice retains duration/waveform, its already-stable ID, and durable temp-file
  cleanup -> TC-269-03/07/17.
- A source/durable pending file survives every transient upload/download or
  local completion failure and is removed only after one authoritative success;
  unrelated direct/group/private artifacts are never deleted -> TC-269-05/06/17.
- A duplicate media replay adds only missing attachment IDs and produces no
  second row, banner, notification, unread increment, reaction flush, or key
  repair -> TC-269-12.

Hard `Do not`:

- Do not change DB version 104, add a migration/column/status/table, or relax
  either `NOT NULL DEFAULT 0` counter constraint.
- Do not weaken the exact parent/attachment CAS, membership requalification,
  media integrity checks, encryption, key storage, relay authorization, or Go
  `TestGroupMediaUnauthorizedPeer` contract.
- Do not serialize an empty ACL as a workaround, treat it as direct mode, add an
  account-ID fallback to the relay, or add a new server-side ACL mutation API.
- Do not retry `not authorized`, `not found`, or integrity-terminal rows, and do
  not widen ordinary group recovery to direct/private media.
- Do not auto-download group private media, bypass user preference, or require a
  conversation route to be open.
- Do not issue relay delete-ack for ordinary group media. A group blob is shared
  by all authorized members; deleting it after the first receiver commits would
  starve later members. Preserve the existing group early-return at
  `download_media_use_case.dart:1214-1222`.
- Do not globally change `InMemoryMediaAttachmentRepository` null semantics;
  use a scoped SQL-defaulting test wrapper and the real repository fixture.
- Do not use iPhone 13, require user taps, reuse the user's personal identity,
  uninstall the production app, or delete broad device/app data. Harness
  cleanup is limited to its explicit disposable DB, identity, files, and
  artifact directory.
- Do not modify unrelated dirty files
  `Test-Flight-Improv/00-INDEX.md`,
  `Test-Flight-Improv/269-review-fixlist.md`,
  `docker-ws/run_fresh_three_phones.sh`,
  `docker-ws/run_fresh_three_phones_result.txt`, or `info.plist`.

Deferred / accepted difference:

- Group document attachments remain owned by future attachment work; this plan
  covers the currently supported image, video, and voice surfaces.
- Posts media is a separate product surface and is not silently folded into
  this group-conversation repair. `attach_post_media_use_case.dart:89-92,288`
  and `pass_post_along_use_case.dart:544-548,595-602` also construct non-empty
  relay ACLs from account peer IDs through raw upload; that verified sibling is
  owned by a dedicated posts-media transport-ACL follow-up. Accordingly,
  TC-269-08 claims every group-conversation media sender, not every use of relay
  group mode in the app.
- A server-side retrofit of ACL metadata on blobs uploaded before this fix is
  not available and would weaken scope/security. Existing pending sender rows
  with preserved local files recover through the corrected bounded retry;
  already-published historical blobs with irreparable old ACL metadata remain
  unavailable and require an explicit future protocol if product policy demands
  backfill. The same immutable ACL snapshot means a device admitted after an
  ordinary upload cannot fetch that older blob; avatar regrant is covered here,
  but ordinary-history regrant/re-upload remains a future protocol decision.
- An unavailable exact phone model at execution is
  `N/A (target unavailable by project policy)`, not a blocker. Re-resolve the
  live matrix. The prepared `ios.device.group_media_269` bundle is physical-only and
  must not be passed to a simulator. If no USB iPhone is live, mark the
  physical Home/suspension leg N/A, run the deterministic native registry suite
  on an available simulator, and report physical hardware confidence as an
  optional follow-up; the default Android paired proof remains required.

Dependencies:

- Plan 268's accepted ordinary Keep-in-chat-only composer contract remains the
  authoring baseline; this plan owns its transport/persistence reliability.
- Plan 263's exact removed-member/membership-phase guards constrain sender retry
  and receiver query authority.
- Existing `MediaDownloadStateRepository.beginMediaDownload` and the process
  single-flight registry remain the concurrency primitive; no new lease schema.
- Device closure requires an available real relay address through
  `MKNOON_RELAY_ADDRESSES`, the pinned live targets, and disposable harness
  identities. No production credential may be written to plan or artifacts.

## Test Contract

Every row has an executable proof and a representative mutation target. Test
names prefixed `P269` are added by this plan.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-269-01 | SQL-default-equivalent retry counters compare `null == 0`, but every non-counter authority field remains exact | `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart::P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field` | unit / direct `MediaAttachment` values differing one field at a time | HEAD rejects `null/0` -> GREEN accepts only counter-equivalent rows and still rejects changed ID, message, status, path, owner, MIME, size, hash, or nonzero count | restore raw counter `==`, or normalize an unrelated field -> this test red | `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field'`; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-02 | Ordinary foreground image/video survives save/reload SQL defaults, invokes upload once, preserves local completion authority, exact-completes once, and publishes one parent | `test/features/groups/presentation/group_conversation_wired_test.dart::P269 ordinary foreground media survives database-defaulted retry counters and reaches exact completion once` | widget/host integration / fidelity-checked SQL-default wrapper, two valid JPEG/MP4 fixtures with conflicting upload timestamp/thumbnail, completion-aware group repo | HEAD upload callback is never reached after `null -> 0` reload -> GREEN one upload per attachment, one completion/publish, both rows `done` with counters zero and original `created_at`/`thumbnail_hash`; upload-owned size/path/hash may change | restore raw comparison, omit either counter, or source local timestamp/thumbnail from upload -> test red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 ordinary foreground media survives database-defaulted retry counters and reaches exact completion once'`; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-03 | Foreground voice crosses the same DB-default boundary exactly once while retaining stable blob ID, duration, waveform, and local completion authority | `test/features/groups/presentation/group_conversation_wired_test.dart::P269 voice foreground media survives database-defaulted retry counters and reaches exact completion once`; existing `::voice stop pre-persists a durable pending attachment and threads a stable blob ID` | widget/host / fidelity-checked SQL-default wrapper, fake recorder/media bridge, conflicting upload timestamp/thumbnail, blocked upload | HEAD strict leaf aborts -> GREEN one upload/publish, one `done` row with both counters zero, original duration/waveform/created-at/thumbnail and claimed ID | omit voice counter/metadata preservation or allocate a second voice ID -> causal/sentinel test red | exact two focused commands in Acceptance Gates; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-04 | Secure/fallback exact completion accepts omitted counters without SQL `NULL` and applies the explicit local-vs-upload field ownership matrix | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::P269 exact group upload completion accepts omitted counters without SQL null`; `::P269 exact group upload completion preserves local authority and accepts upload owned fields`; `::P269 SQL default wrapper matches production schema for omitted and explicit null counters` | repository integration / `MediaRepositoryRealDbFixture`, production-schema SQLite FFI, secure-key store double, completed row deliberately conflicting with expected local and upload-owned fields | HEAD omitted counters throw; with counters supplied HEAD overwrites `created_at`/`thumbnail_hash` -> GREEN both paths return true, raw locally owned fields/counters equal expected, upload-owned size/path/hash/encryption fields equal completion, raw status is `done`, secure key stays out of SQL; wrapper and real fixture agree that omitted defaults to zero and explicit null rejects | source local timestamp/thumbnail from upload, omit either counter merge, blanket-freeze upload-owned size, or let wrapper accept explicit null -> one test red | exact three focused commands in Acceptance Gates; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-05 | Incomplete-group retry carries both persisted counters and local authority through success, settles once, and an explicit second pass performs zero uploads | `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart::P269 successful incomplete-group recovery carries both persisted counters into completion and settles only once` | application host / completion-aware repo, real retry selection, successful connectivity probe where production-like, upload spy, durable local file with timestamp/thumbnail | HEAD completion receives a null download counter or overwrites local authority and a second pass uploads again -> GREEN first pass preserves counters/timestamp/thumbnail and commits/publishes once; explicitly invoked second pass returns zero and makes no upload | drop either counter/local field carry, leave row `upload_pending`, or infer zero work without invoking the pass -> test red | `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 successful incomplete-group recovery carries both persisted counters into completion and settles only once'`; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-06 | Foreground/retry completion exceptions and unchanged-authority false results consume the existing bounded upload budget exactly; genuine lost CAS and unrelated artifacts stay untouched | `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart::P269 completion persistence failures advance exact bounded sequence and discriminate lost authority`; `test/features/groups/presentation/group_conversation_wired_test.dart::P269 foreground completion failure projects bounded only while exact pending authority survives`; `test/core/database/helpers/group_messages_db_helpers_sending_test.dart::P269 sending sweeper preserves parents with pending group uploads in both age modes` | application/widget/DB host / completion repo throwing or false, exact re-read, production projection, durable file, competing parent mutation, direct/group/private sibling files, four explicit use-case invocations, successful probe when enabled | HEAD exception logs forever and false silently reuploads -> GREEN projections are exactly `(1,upload_pending)`, `(2,upload_pending)`, `(3,upload_failed)`, source/siblings survive byte-identical, fourth pass uploads zero; unchanged false projects once, changed authority projects zero; real sweeper never changes a parent owning `upload_pending` | terminalize first, reuse terminal consumer failure, skip exact re-read, project lost CAS, delete a sibling, or remove either sweeper exclusion -> one test red | exact three focused commands; all three files already occur once in `GROUP_TESTS` and must not be re-added; AUTO feature/core-host globs |
| TC-269-07 | Ordinary multi-media foreground lease owns the real durable blob IDs before any row becomes observable through settlement; voice preserves the same invariant | `test/features/groups/presentation/group_conversation_wired_test.dart::P269 ordinary multi-media foreground lease owns every durable persisted blob ID until settlement`; extend existing `::voice stop pre-persists a durable pending attachment and threads a stable blob ID` | widget/host / process-wide tracker, two preallocated attachment IDs, save-observer that synchronously launches a competing periodic claim at first row visibility, blocked upload | HEAD persisted IDs are unowned and competitor claims them -> GREEN every durable ID was already claimed when save makes it visible, competitor loses, all release exactly once after settlement; voice stays GREEN | generate UUIDs inside durable prep, claim after save, or claim optimistic-only IDs -> ordinary test red; stop claiming voice ID -> voice sentinel red | exact two focused commands in Acceptance Gates; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-08 | Every group-conversation media sender—foreground, voice, retry, external share/forward, send-time requalification, and avatar regrant—emits unique active transport IDs, excludes revoked/blank devices, and uses legacy account transport only when no explicit roster exists | `test/features/groups/application/group_media_allowed_peers_test.dart::P269 group media ACL uses active device transport identities with revoked-safe legacy fallback`; `test/features/groups/integration/group_media_fanout_test.dart::P269 group media fanout ACL never emits account or device IDs when transport IDs differ`; `test/features/share/application/share_batch_delivery_coordinator_test.dart::P269 external group media share uses active transport ACL and never account or device IDs`; extend `contact_picker_wired_test.dart::batch invite reuploads existing avatar for expanded member ACL before signing invites` and `group_info_wired_test.dart::GCA-103 post-invite avatar upload includes late invitee in allowedPeers` | unit + host integration / account ID differs from active transport ID; device ID may equal transport; duplicate, revoked, all-revoked, legacy, helper, composer-fanout proof, share, and avatar fixtures | HEAD helper/share emit account IDs -> GREEN every scoped path emits deterministic unique active transports; all-revoked explicit roster yields empty; legacy-only member yields legacy transport | leave share's direct member map, substitute `member.peerId`, emit device IDs, use raw `activeDevices`, resurrect revoked legacy, or claim posts are covered -> one named test red | exact five focused commands; add helper, `group_media_fanout_test.dart`, and `contact_picker_wired_test.dart` to `GROUP_TESTS`; share/group-info already registered; AUTO feature-host glob |
| TC-269-09 | Empty/blank group ACL fails closed at ordinary/voice preflight, shared upload leaf, and raw avatar upload before each path's first claimed side effect; null ACL still executes direct mode | `test/features/groups/presentation/group_conversation_wired_test.dart::P269 ordinary and voice empty ACL preflight preserves sources with zero durable or crypto effects`; `test/features/conversation/application/upload_media_use_case_test.dart::P269 explicit empty group ACL fails closed before encryption or bridge upload`; `test/features/groups/application/group_avatar_storage_test.dart::P269 group avatar empty ACL fails before file access or bridge upload`; `test/features/groups/presentation/group_info_wired_test.dart::P269 group avatar edit never falls back to account ID when member ACL is empty`; existing direct/group MIME sentinels | widget + application host / valid JPEG/voice/avatar, recording repositories/file manager/crypto bridge, empty/blank/deduped ACLs, roster change after preflight, null direct ACL | HEAD may copy/save ordinary or voice data and raw avatar serializes direct mode -> GREEN typed `EMPTY_GROUP_MEDIA_ACL`, composer/recording source retained, zero durable copy/parent/attachment/keygen/encrypt/upload/file-read for the applicable path; late empty leaf also fails; null direct and non-empty group remain GREEN | guard only `uploadMedia`, keep group-info fallback, omit avatar guard, serialize empty, or reject null direct -> one named test red | exact focused commands in Acceptance Gates; add upload/avatar tests to `GROUP_TESTS`, retain upload in `ONE_TO_ONE_TESTS`, wired/group-info already registered, AUTO feature-host glob |
| TC-269-10 | A valid `.heif` group image is canonicalized to `image/heic`, uploaded, persisted, and published once | `test/features/groups/presentation/group_conversation_wired_test.dart::P269 group composer canonicalizes heif to image heic and uploads and publishes once`; `test/core/media/group_media_mime_policy_test.dart` | widget/host + unit sentinel / valid `ftyp/mif1` fixture, fake bridge/media manager | HEAD becomes octet-stream and is rejected -> GREEN uploader sees `image/heic`, one row reaches `done`, one parent publishes; invalid types remain rejected | remove `.heif` mapping, map it to unsupported `image/heif`, or broaden arbitrary octet-stream acceptance -> causal/policy test red | exact two focused commands in Acceptance Gates; wired existing `GROUP_TESTS`, MIME policy existing core registration |
| TC-269-11 | Ordinary-group transient/integrity outcomes use one atomic no-resurrection transition; relay `not authorized`/`not found` stay immediately terminal without budget use; direct/private rows and sibling files do not change | `test/features/conversation/application/download_media_use_case_test.dart::P269 ordinary group transient failure uses one atomic retry transition while relay authorization denial stays terminal`; `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::P269 group download failure CAS is atomic and deletion journal cannot resurrect media`; exact not-found, hash, direct/private, and group-private sentinels | application + real-schema repository / ordinary group row, transient/auth/not-found/integrity failures, DB throw, delete race/journal, direct/group/private sibling rows/files | HEAD split swallowed writes can reinsert a deleted row -> GREEN status/count/path changes atomically from exact authority; absent/deleted/journal stay absent, DB fault and siblings stay byte-identical; authorization/not-found emit their generic exact reason and consume zero budget; no group delete-ack occurs | restore split save, omit journal/live-parent guard, label denial as legacy, issue group delete-ack, mutate sibling, or widen to direct/private -> causal/sentinel red | add only `download_media_use_case_test.dart` to `GROUP_TESTS` while retaining it in `ONE_TO_ONE_TESTS`; repository test already occurs once in `GROUP_TESTS` and must not be re-added; exact sentinels/AUTO feature-host |
| TC-269-12 | The detailed API covers all five production dedupe exits and reports only exact newly persisted media IDs; stable-identity enrichment starts one recovery, while identical/guard-refused/content-only duplicates start zero | `test/features/groups/application/handle_incoming_group_message_use_case_test.dart::P269 detailed duplicate outcome reports exact persisted media across every dedupe branch`; `test/features/groups/application/group_message_listener_test.dart::P269 duplicate replay media enrichment starts exactly one canonical download without a second delivery side effect` | application host / table over same-ID compatibility, event-log same-ID, logical-delivery, logical-media-retry, content-only, identical third replay, guarded-save false, reconciled self echo; delayed bridge/delivery spies | HEAD four enrichment-capable exits return null after best-effort save and content-only returns null without save -> GREEN delivered preserves new/self-echo behavior; successful stable branches return canonical row plus exact IDs and one transfer; existing/guard-refused/content-only are ignored with zero writes/recovery; zero duplicate side effects | derive IDs from wire descriptors, ignore save bool, enrich heuristic content-only match, omit any exit, misclassify self echo, or emit delivery side effects -> table/listener red | exact two focused commands; both existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-13 | Cursor-paged durable query returns only incoming ordinary group rows in recoverable states under budget/current authority, stable `(created_at,id)` order, with separate scan/transfer bounds | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::P269 recoverable group download query is authority scoped cursor paged and cannot starve later rows` | repository integration / production-schema SQLite FFI matrix: direct/group, incoming/outgoing, active/removed/deleted/tombstoned, ordinary/protected/view-once/disappearing, pending/downloading/failed counts 0/2/3, terminal/integrity/upload; more than one denied page before an eligible row | HEAD has no query -> GREEN pages without repeats/omissions and reaches the later eligible row while every private lifecycle, direct/outgoing/removed/terminal row stays byte-identical | remove owner/parent/policy/authority/budget/status/cursor predicate, include any private lifecycle, fixed first page, coupled limits, or unstable order -> test red | exact focused command; repository test already in `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-14 | Shared recovery converges pending, interrupted `downloading`, and under-budget `failed` ordinary group media from durable state without opening the conversation; it scans past denied pages and recovers direct-drain enrichment | `test/features/groups/application/retry_incomplete_group_downloads_use_case_test.dart::P269 group download recovery pages past denied rows and converges eligible durable media exactly once` | application host / fresh use-case/coordinator over persisted rows, low scan page, direct offline-drain duplicate-enriched row, more than one denied page then valid encrypted/hash row, policy/bridge/files, unrelated private/group files | HEAD has no use case -> GREEN eligible and direct-drain-enriched rows each converge once; protected/view-once/disappearing/terminal/policy-denied rows and sibling files stay byte-identical; explicit second sweep zero | stop after denied page, filter pending-only, bypass policy, include private/terminal, drop direct-drain row, or omit claim/commit CAS -> test red | exact focused command; add to `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-15 | New/enriched delivery, every automatic route-open/live refresh, resume, node-ready restore, and explicitly driven periodic passes share one coordinator; overlap coalesces, stop waits, and early restore/account denial mutate nothing | `test/features/groups/application/group_message_listener_test.dart::P269 overlapping listener route and recovery sweep share one transfer and stop awaits tracked recovery`; `test/features/groups/presentation/group_conversation_wired_test.dart::P269 automatic route media recovery delegates to shared coordinator while explicit retry stays user owned`; `test/core/lifecycle/handle_app_resumed_group_download_recovery_test.dart::P269 resume runs group media recovery after first group inbox drain`; `test/core/services/pending_message_retrier_group_download_recovery_test.dart::P269 restored not ready and account denied do no work before node ready coalesced recovery`; `test/features/groups/integration/group_media_reliability_wiring_test.dart::P269 every production group conversation invocation shares one gated download coordinator` | host application/lifecycle + source wiring / delayed bridge, direct-drain enriched fixture, readiness/account gates; enumerate every `GroupConversationWired(` under `lib/**`, exclude declaration, baseline five invocations in main/group-list/create-picker/orbit/feed | HEAD route calls `downloadMedia` directly and no durable callbacks exist -> GREEN one transfer/commit/UI refresh, stop waits, drain enrichment precedes resume sweep, early/not-ready/denied zero, ready/explicit periodic coalesce, every current/future invocation carries one coordinator | retain raw route call, omit orbit/feed/any discovered invocation, run unready, bypass account gate, duplicate coordinator, untrack, or reorder before drain -> one named test red | exact five commands; register all in `GROUP_TESTS`; core files AUTO core-host, group files AUTO feature-host |
| TC-269-16 | Discussion and announcement auto-download consult the shared preference immediately before every paged/listener/route transfer; deny leaves the row unchanged and cannot starve a later allowed row | `test/features/groups/application/group_message_listener_test.dart::P269 discussion and announcement media consult shared auto download policy immediately before transfer`; TC-269-14 denied-page case | application host / `RecordingMediaAutoDownloadDecider`, discussion/announcement parents, pending rows, preference flip between selection/transfer, denied older page then allowed row, bridge/status spies | HEAD denied preference still downloads -> GREEN correct conversation kind/group owner; deny is zero mutation/bridge, allow transfers once, later allowed row is reached | bypass/cache decider, hardcode kind, mutate denied row, or stop paging at denial -> causal test red | exact listener and TC-269-14 commands; existing/new `GROUP_TESTS`, AUTO feature-host glob |
| TC-269-17 | A background receiver owns one critical task around the tracked batch; grant/refusal, success/throw, stop-waits, and deterministic native expiry produce one terminal path without regressing any existing caller | `test/features/groups/application/group_message_listener_media_background_task_test.dart::P269 background group media receive balances grant refusal success throw and stop wait`; `ios/RunnerTests/GoBridgeCriticalTaskTests.swift::test_expirationThenLateDartEndEndsNativeTaskExactlyOnce`; existing normal/distinct-task suite; `feed_wired_bg_task_test.dart::bg:begin happens before inline send transport and bg:end happens after success` | host + native / `BackgroundTaskManaging` fake injected through defaulted `GoBridge` initializer into `CriticalTaskRegistry`, Dart begin/end fakes, lifecycle, delayed transfer, durable files | HEAD has no receive owner and native `bgEnd` blindly re-ends expired IDs -> GREEN registry atomically removes one live ID on normal end or injected expiration; late end no-ops; refusal has no end; throw stays retryable; stop waits; ordinary begin/end and multiple IDs remain balanced; existing feed caller stays ordered | remove begin/finally, use global mutable test registry, double-end, regress generic caller, terminalize interruption, or return from stop early -> host/native/sentinel red | focused Flutter, feed sentinel, and exact native suite commands; add receiver test to `GROUP_TESTS`; shared native suite is causal plus preservation |
| TC-269-18 | The two-role harness consumes centrally prepared artifacts, performs zero child builds, has strict scenario/device/identity parsing, exact group-gate membership, a reusable validated XCUITest selector, and one non-circular structured Sims result | `test/features/groups/integration/group_media_reliability_criteria_test.dart::P269 reliability criteria bind exact v1 group media artifact schema`; `test/integration/group_media_reliability_runner_contract_test.dart::P269 runner requires prepared main artifact two roles and one Sims evidence envelope`; new group-gate registration shell contract; `test/integration/ios_xctestrun_relocator_test.dart::P269 test without building accepts validated group media selector and preserves notification default`; discovery/list/legacy contracts | host criteria/script / complete plus one-field-corrupt JSON corpus, prepared artifacts, build-guard log, unsafe IDs, dynamic exact `GROUP_TESTS` block parser, Android capability `groups.media_send_reliability` on `android.e2e.group_media_269` | HEAD scenarios/contracts absent and selector hardcodes `NotificationTapUITests` -> GREEN exact schema/negative corpus cannot false-green; every required full test path occurs once inside `GROUP_TESTS`; Android consumes prepared APK and emits one path/SHA/validator envelope; generic selector accepts only validated `RunnerUITests/<Class>/<method>` and preserves notification behavior | let runner/test invent schema together without negative mutations, inspect outside the group array, use basename/line range, child-build, multiple sentinel, unsafe selector, missing validator, or dispatcher-only profile -> contract red | exact criteria/runner/registration/relocator/discovery/list/selector/completeness/`sims-contracts`/filtered Sims commands; runner contract registered once; manifest owns TC-269-19 only |
| TC-269-19 | Fresh real-relay Pixel + emulator send JPEG, MP4, and voice once under active transport ACL; a host-owned real receiver process death after JPEG claim recovers once; reopened role SQLCipher DBs and explicit zero-work second passes attest settlement | scenario `group_media_foreground_retry_acl_roundtrip` in `integration_test/scripts/run_group_media_send_reliability.dart` | production-critical pair / USB Pixel `21071FDF600CSC` + `emulator-5554`, prepared `android.e2e.group_media_269`, compile-gated post-claim/pre-commit barrier, host ADB controller/app-state guard, real relay, disposable distinct account/transport identities, production SQLCipher role DBs | Device-only proof: HEAD sender completion fails and scenario absent -> GREEN one upload/publication per kind; host observes atomic JPEG barrier and old PID, resolves validated package, force-stops, proves PID gone, relaunches launcher without group route with fresh PID; app attests `priorStatus=downloading` before JPEG attempt 2; JPEG attempts two, siblings one; same sender/receiver DBs reopen with exact rows; harness invokes the same gated periodic callbacks twice and the second returns zero upload/download | use in-process throw, fail to prove PID transition/prior durable status, open group to recover, interrupt upload, attest probe DB, wait/infer timer pass, accept wrong counts, or misuse delete-ack -> artifact/criteria red | direct plus Sims capability commands; required closure evidence |
| TC-269-20 | Pixel sender + available physical iOS receiver proves fast background success and deterministic Home/forced-interruption/relaunch recovery; native unit proof separately owns expiry-then-late-end exactness | scenario `group_media_ios_receiver_background_recovery`; `ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift` using `XCUIDevice.shared.press(.home)`; generalized relocator selector | iOS-specific pair / Pixel + live USB iPhone, prepared physical app/XCTest bundle, real relay/bridge/role DB, fresh identities, named durable pre-commit barrier, host `test-without-building`, two phases | Device-only proof: owner/controller absent on HEAD -> GREEN phase A records granted normal end; phase B records terminal path exactly `interrupted`, pauses after durable claim, presses Home, host terminates, relaunches without group, and resume-after-drain converges once with one UI effect; TC-269-17 deterministically records `expired` and late-end no-op. Optional natural-expiry run is evidence, not a gate | accept ambiguous terminal path, require flaky natural expiry, build/skip named XCUITest, use sleep-only backgrounding, omit Home/relaunch, misuse physical bundle on simulator, or duplicate effects -> red | prepare physical bundle and run exact direct command while a USB iPhone is available; otherwise physical leg is N/A and native simulator suite remains required; zero child build, exact selector, no iPhone 13 |

### Test Notes

- TC-269-02/03 must not globally modify the in-memory media repository. Their
  scoped wrapper applies only the production schema behavior relevant to this
  regression: omitted counters reload as zero, while an explicit-null update
  rejects like `NOT NULL`. TC-269-04 differentially runs both cases through the
  wrapper and `MediaRepositoryRealDbFixture` so fake drift cannot green the
  widget rows. The fixture is production-schema SQLite FFI, not SQLCipher; only
  TC-269-19/20 may claim production SQLCipher device evidence.
- TC-269-01 permits `null == 0` only for the two local retry counters. A mutation
  that makes path/status/hash/owner or positive retry counts fuzzy is a failure;
  the strict Plan 263 membership and parent/attachment CAS remains intact.
- TC-269-05 records the upload count before and after a second full retry pass;
  a `done` assertion alone is insufficient because it would miss duplicate
  bandwidth/publication. It must also assert absence of the captured
  `RETRY_INCOMPLETE_GROUP_UPLOAD_ERROR`/SQL constraint signature.
- TC-269-04's field matrix uses conflicting values deliberately. Locally owned
  creation time, thumbnail hash, and both counters must equal the expected row;
  upload-owned fields must equal completion. A blanket pre/post equality would
  be wrong because measured size and other normalized upload outputs may
  legitimately change.
- TC-269-06 uses the existing upload retry ceiling and failure projection. A new
  status, silent swallow, unconditional source deletion, or infinite retry is
  out of scope. The post-upload local-completion failure must be synthesized as
  bounded retryable rather than reusing the existing terminal consumer-boundary
  constant. A false result projects only after an exact re-read proves the row
  still owns unchanged pending authority. Manual retry remains possible once
  the local persistence issue is repaired. Unit invocations may leave
  `requireOsConnectivity` at its documented default `false`; any retrier-like
  fixture sets it `true` and injects a successful probe so it cannot green by
  short-circuiting. The production sending sweeper already excludes parents
  with `upload_pending` group attachments in both age branches at
  `group_messages_db_helpers.dart:1217-1246`; pin that invariant and do not add
  a redundant second exclusion.
- TC-269-07's competitor fires synchronously from the persistence observer; a
  test that waits until upload is blocked would miss the save-before-lease race.
- TC-269-08 unit fixtures may give account, device, and transport different
  values, but device proof requires only the production discriminator
  `accountPeerId != active transportPeerId`; `deviceId == transportPeerId` is a
  valid production identity. The expected ACL includes active transports only,
  including the external share path and
  legacy fallback only for members whose explicit roster is absent. An
  all-revoked explicit roster must stay empty so revocation cannot resurrect an
  account-level transport.
- TC-269-09 has two guards by design: caller preflight prevents ordinary/voice
  copy/save/source cleanup, while the shared leaf prevents a roster change
  between preflight and transport. Raw avatar upload rejects before file access.
  Merely serializing `[]` fails because Go `omitempty` and relay
  `len(AllowedPeers) > 0` still classify it as direct. Non-empty group and null
  direct sentinels pin both modes. All three guard sites use the literal
  `EMPTY_GROUP_MEDIA_ACL`; avatar preserves its nullable API but emits that
  reason before its first file read.
- TC-269-11 does not add receiver authorization grace. The relay ACL is stored
  at upload and cannot converge through a receiver retry. Every ordinary group
  failure transition is a single guarded DB statement; its tests interleave
  delete-for-me and inject a DB fault to prove zero resurrection/partial tuple.
  Exact not-authorized, not-found, content-hash, direct, and terminal-private
  sentinels are literal gates, not broad-file substitutes. The client can
  observe generic `not authorized` but cannot distinguish a pre-fix ACL from a
  late-admitted/revoked device; do not emit a false legacy-specific reason.
  Group relay delete-ack remains forbidden because the blob serves multiple
  members.
- TC-269-12 adds a detailed handler API beside the current nullable wrapper so
  the existing caller/test population stays source-compatible. `delivered`
  preserves both new-message and reconciled-self-echo non-null behavior. Its save helper
  returns only IDs actually committed (including guarded-save `true`); existing
  IDs and `false` are not enrichment. Only the listener consumes a non-empty
  `duplicateEnriched` outcome; it never calls `_emitGroupMessage`, notification,
  unread, reaction-flush, or key-repair branches for that outcome. Content-only
  dedupe is the fifth branch and stays ignored because it has no stable wire
  identity, even though a heuristic canonical row can be found.
- TC-269-13 query authority is derived from existing group message/media state;
  no schema change is justified. Cursor progress is independent of transfer
  count, so a denied page cannot repeat forever. `downloading` is retryable after
  process death. In-process overlap still joins the existing single-flight key,
  and begin/commit/failure CAS rejects a lost claim.
- TC-269-14/16 ask the policy immediately before each transfer, not merely when
  selecting a batch. Preference changes between selection and network access
  therefore fail closed without mutating the row. TC-269-14's host “restart” is
  a fresh use-case/coordinator over persisted rows, not process death; only
  TC-269-19's force-stop/fresh-PID leg closes that claim. A direct offline-drain
  duplicate-enrichment fixture proves nullable-wrapper callers are recovered by
  the later sweep; key repair remains wrapper-compatible and periodic recovery
  owns any durable row it leaves.
- TC-269-15's source contract dynamically enumerates every invocation under
  `lib/**`, excluding the constructor declaration, with the current baseline
  `main.dart`, group list, create picker, Orbit, and Feed. It proves one coordinator
  reaches all automatic triggers, while explicit retry/private open stays
  user-owned. The early OS-restored flush never runs downloads until node/relay
  readiness and the account-migration network gate both allow it.
- TC-269-17 acquires a receive critical task only for an eligible batch while
  lifecycle is not resumed. A null/refused task ID is a supported no-op. Stop
  waits for tracked work; there is no invented cancellation path. Swift owns a
  live-ID registry so expiration and late Dart `finally` cannot both end the
  native task. `CriticalTaskRegistry` receives a `BackgroundTaskManaging`
  dependency through a defaulted `GoBridge` initializer; the fake, not
  production, records ended IDs. Because the registry is process-wide, generic
  normal begin/end, multiple-ID native tests and the existing Feed ordering
  sentinel protect non-group callers.
- TC-269-18 pins artifact schema `mknoon.group-media-reliability.v1`. Required
  top-level keys are `schema`, `run_id`, `scenario`, `prepared_artifact`,
  `device_roles`, `identity_fingerprints`,
  `account_vs_transport_discriminator`, `acl_entries`, `media`,
  `role_databases`, `retry_passes`, `flow_events`, and `cleanup`. `media` carries
  `uploads_per_blob`, `publications_per_message`, and
  `download_attempts:{jpeg:2,mp4:1,voice:1}`, plus exact receiver
  `rendered_surfaces:{jpeg:1,mp4:1,voice:1}`. `retry_passes` carries explicit
  second-pass upload/download zeros. `role_databases.sender` and `.receiver`
  each require sanitized `role_db_path`, non-empty `cipher_version`,
  `user_version:104`, reopen marker, and exact run/message/blob/status/counters.
  `cleanup` binds the dedicated package/profile/artifact digest to distinct
  pre/post reset receipts for both roles, requires the app to remain installed,
  and proves zero production-package, uninstall, `pm clear`, or broad-delete
  commands from the audited real command paths.
  One-field removal/type/value mutation fixtures must all fail. The Sims
  sentinel remains exactly one path/SHA-256/validator envelope with no child
  build. `acl_entries` contains run-scoped SHA-256 transport fingerprints that
  can be matched to the active-device fingerprints, never raw peer IDs; no
  keys, tokens, media bytes, full peer IDs, or user-revealing absolute DB paths
  are retained.
- TC-269-18's group-registration contract dynamically parses only the
  `readonly GROUP_TESTS=(` block through its closing `)`, discovers every Dart
  test file containing a `P269` test plus the explicitly extended
  `contact_picker_wired_test.dart`, and requires each exact full path exactly
  once. It must not use basenames, hard-coded line ranges, or accept an entry
  found later in `OPTIONAL_MANUAL_TESTS`. `completeness-check` remains a global
  classification gate and is not evidence of curated group membership.
- TC-269-19's compile-gated barrier is added to the centrally prepared main APK;
  it does not already exist on HEAD. The external host waits for its atomic
  post-claim/pre-commit marker, records the validated package/PID, force-stops,
  proves the old PID gone, explicitly relaunches the launcher without a group
  route, proves a fresh PID, and requires the app to attest
  `priorStatus=downloading` before attempt two. The fixture invokes the same
  readiness/account/connectivity-gated periodic callbacks on command—never a
  shortened timer or five-minute inference—and records start/end/work counts.
  Attestation reopens the role DB containing the exact IDs; a probe DB fails.
- TC-269-20 is separate because UIApplication suspension and the native critical
  task cannot be proven by the default Android pair. XCUITest drives Home and
  a deterministic forced-interruption/relaunch phase and records the terminal
  path rather than accepting an ambiguous branch. Injected native TC-269-17,
  not wall-clock device timing, proves expiry then late end. Natural expiration
  is optional evidence. The currently wired iPhone 11 is eligible; iPhone 13 is
  excluded. If no USB iPhone is available, the physical leg is N/A and the
  native simulator suite remains required; never install the physical bundle
  on a simulator.

## Execution Waves And GO/STOP Checkpoints

The plan is deliberately split because it changes a large widget/repository
surface, process-wide lifecycle wiring, native Swift ownership, and a greenfield
device harness. A wave ends with diff review, an Execution Progress row, and an
explicit GO/STOP decision; it does not mandate a Git commit.

| Wave | Rows / ownership | Required checkpoint gate | GO condition |
|---|---|---|---|
| W1 Sender persistence | TC-269-01..07 and 10 | all W1 focused RED→GREEN commands, sender/direct preservation sentinels, `./scripts/run_test_gates.sh groups` | counter and field ownership, bounded failure, durable ID lease, and HEIF are green with no non-counter CAS relaxation |
| W2 ACL fail-closed | TC-269-08/09 | ACL/avatar/share focused commands, exact Go authorization sentinels, curated `groups` | every scoped group-conversation sender uses active transports and empty ACL has zero side effects while null direct stays green |
| W3 Receiver recovery | TC-269-11..16 | receiver/private/announcement focused commands, curated `groups`, then one justified `core-host-all` after core lifecycle/repository surfaces settle | atomic no-resurrection failure, five dedupe exits, paging/policy, and every automatic route are green |
| W4 Native/harness/device | TC-269-17..20 | native suite, shared-caller sentinel, exact registration/runner/Sims contracts, prepared Android proof, available physical-iOS proof, then final justified feature/core closure | exact task ownership, non-circular artifacts, real Android process death, and target-bounded iOS evidence close honestly |

## Implementation Steps

1. Snapshot `git status --short`; preserve the unrelated dirty baseline. Before
   the first production edit, archive a sanitized excerpt containing the Pixel
   SQL `NOT NULL` signature and both relay `ok:true` responses under the Plan
   269 Sims artifact directory with path/SHA-256 in Execution Progress. If the
   original logs are no longer recoverable, record that provenance gap and
   reproduce/capture a fresh HEAD baseline rather than inventing an artifact.
2. Author every W1 test named in TC-269-01..07/10, including the independent
   counter-null and conflicting-field ownership legs, wrapper differential,
   sweeper sentinel, and lease-at-first-visibility race. Run each focused
   command and record its causal RED before its owning production edit.
3. Normalize only the two counters in `sameExactGroupRetryAttachment`.
   Initialize both on ordinary/voice rows. Apply the explicit completion
   ownership matrix at foreground, retry, secure-repository, and fallback DB
   boundaries; preserve local timestamp/thumbnail/counters while accepting the
   enumerated upload-owned outputs. Stop-if any other exact authority becomes
   fuzzy, upload-owned size is frozen, or a migration appears necessary.
4. Project post-upload completion exceptions and unchanged-authority false
   results through the existing bounded retry path; genuine lost CAS remains
   untouched. Allocate/claim ordinary durable IDs before row visibility,
   preserve voice's ID, and add `.heif -> image/heic`. Re-run W1 tests to GREEN,
   execute the W1 checkpoint, record GO/STOP, and do not proceed on red.
5. Author TC-269-08/09 tests first and observe the helper/share/avatar/account-ID
   and empty-ACL causal REDs. Then use active device transport IDs at the actual
   conversation/retry/share/avatar and final equality call sites, remove the
   group-info fallback, and enforce the shared `EMPTY_GROUP_MEDIA_ACL` contract
   before each path's first side effect. Do not edit posts or Go authorization.
   Re-run to GREEN and complete the W2 checkpoint before receiver work.
6. Author TC-269-11 REDs before changing failure persistence. Add one exact
   owner/message/status/path CAS for ordinary-group transient/terminal/integrity
   failure with live-parent and deletion-journal guards. Never fall back to a
   preserving save after lost CAS, never mutate sibling lanes/files, and never
   relay-delete a shared group blob.
7. Author TC-269-12's five-exit table and listener side-effect RED before API
   work. Add `IncomingGroupMessageDetailedOutcome` and
   `handleIncomingGroupMessageDetailed`, retain the nullable wrapper, return
   exact committed IDs for four stable branches, keep content-only ignored,
   and let only the listener schedule canonical recovery.
8. Author TC-269-13/14/16 REDs before repository/recovery changes. Add the
   ordinary incoming query and `retryIncompleteGroupDownloads` with stable
   cursor paging, independent scan/transfer limits, immediate authority/policy
   re-read, claim/commit/failure CAS, and existing single-flight. Include a
   direct-drain enrichment fixture and every private lifecycle exclusion.
9. Author all TC-269-15 trigger/wiring REDs, including recursive invocation
   enumeration. Construct one coordinator in `main.dart`; thread it through
   main, group list, create picker, Orbit, and Feed into automatic screen work,
   listener, resume-after-drain, ready network recovery, and explicitly
   invokable periodic callbacks. Preserve manual/private routes and the early
   unready/account gate. Re-run W3 tests and checkpoint; do not proceed on red.
10. Author TC-269-17 native/host/shared-caller REDs. Implement an injected
    `BackgroundTaskManaging` plus `CriticalTaskRegistry` via the defaulted
    `GoBridge` initializer, then wrap eligible non-resumed receive batches in
    Dart begin/finally. Deterministically test expiration/late-end; preserve
    generic normal/multiple tasks and unchanged Dart callers.
11. Author TC-269-18 criteria, negative schema corpus, exact dynamic
    `GROUP_TESTS` membership contract, runner/parser/build-guard contracts, and
    relocator selector REDs. Then register each host proof exactly once, add the
    two-scenario prepared-artifact runner and Android manifest capability, and
    generalize `iosTestWithoutBuildingArguments` to a validated full selector
    while preserving the notification default. Run discovery, completeness,
    `sims-contracts`, and filtered Sims dry/actual planning before devices.
12. Author the TC-269-19/20 barrier, PID, explicit-pass, terminal-path, and
    XCUITest criteria before device implementation; the absent scenarios/hooks
    are their RED. Add the compile-gated main-app barrier and external host
    controller, re-resolve live targets, then run the prepared Pixel/emulator
    real-relay kill/relaunch proof with fresh identities and exact role DBs.
    Run the physical iOS Home/forced-interruption proof only on a live USB
    iPhone; otherwise mark that physical leg N/A and retain simulator-native
    registry proof. Do not use iPhone 13.
13. Complete W4 and final closure: focused tests, exact relay/native/shared
    sentinels, exact group registration, curated `groups`, pinned `transport`,
    justified final `feature-host-all`/`core-host-all`, analyzer, whitespace,
    scope diff, and one incremental Graphify refresh. Do not run full `host-all`
    for this individual plan.

## Risks And Blind Spots

- Counter normalization could accidentally weaken exact-CAS authority ->
  TC-269-01 mutates every sibling field independently; membership/order
  sentinels remain required.
- The counter fix unmasks completion-field corruption -> TC-269-02..05 apply
  conflicting expected/upload values and prove local timestamp/thumbnail/
  counters survive while legitimate upload-owned size/path/hash changes land.
- A relay success followed by local failure can consume bandwidth before the
  bounded ceiling -> TC-269-05/06 prove one settlement or a terminal automatic
  stop while retaining manual recovery bytes. No protocol receipt exists to
  complete the DB transaction atomically with relay custody.
- Active device rosters may be empty after revocation -> TC-269-08/09 fail
  closed before ordinary/voice/avatar side effects, preventing accidental
  direct-mode exposure; share/forward and avatar tests pin every scoped
  group-conversation caller. Posts are explicitly deferred, not implied fixed.
- A receiver retry cannot repair immutable relay ACL metadata -> TC-269-11
  keeps `not authorized` immediately terminal; TC-269-08/19 prevent denial by
  constructing the correct transport ACL at upload.
- Split failure writes can resurrect delete-for-me media -> TC-269-11 forces one
  deletion-journal-aware CAS and proves a DB fault leaves the prior tuple exact;
  the group lane never delete-acks the shared relay blob.
- Duplicate enrichment and recovery could double emit -> TC-269-12/15 count
  every timeline/notification/unread/reaction/key-repair and transfer effect.
- Lifecycle / derived-state durability: TC-269-13/14/15 cover restart from
  `downloading`, paging beyond denied rows, route/listener overlap, early
  restored-but-not-ready no-op, node-ready/periodic recovery, resume ordering,
  account gate, and listener shutdown. Those host rows simulate restart over
  durable state; TC-269-19 alone proves real Android process death/fresh PID.
- Sibling-surface consistency: TC-269-02/03/05/07 cover ordinary, voice, and
  retry sender paths; TC-269-16 covers discussion and announcement receiver
  policy; direct/private preservation is TC-269-09/11/13.
- iOS can refuse or expire a background task -> TC-269-17 deterministically
  proves refusal/normal/expiry ownership; TC-269-20 proves real Home plus forced
  interruption/relaunch without making natural expiry a flaky closure gate.
- Device artifacts can false-green on UI-only success or a separate DB probe ->
  TC-269-18/19 require a centrally prepared main APK, zero child builds, one
  structured result, relay/count/hash, and exact reopened role-DB facts.
- Destructive-action side effects: the harness uses explicit disposable DB and
  identity namespaces, never broad paths/uninstall/user identity; TC-269-18
  validates scope and teardown artifacts.
- Invariant re-verification under new transitions: exact Go relay denial,
  Plan-263 membership/B3 ordering, integrity terminalization, private media
  lifecycle, and direct transport remain named preservation gates.

## Gate Cadence

- Per-plan closure: causal focused tests and preservation sentinels; exact Go
  relay authorization tests; `./scripts/run_test_gates.sh groups`; pinned
  `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport` because
  shared media/bridge request classification changes; justified
  `feature-host-all` for group/conversation production surfaces and
  `core-host-all` for lifecycle/repository/retrier surfaces; discovery/manifest
  checks plus the filtered prepared-build Sims capability; required Android
  real-relay and deterministic XCUITest-controlled iOS proofs; analyzer,
  whitespace, scope, and graph refresh.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the named
  **Group Media Reliability 269** dependency wave is complete, and once at
  final rollout/release closure.
- Shared tests outside feature/core globs: exact Go relay command, runner/Sims
  contract, shell discovery contract, native iOS critical-task test, filtered
  Sims capability, and both direct boundary commands below. Registration under
  a later broad gate does not replace these exact executions.

## Device/Relay Proof Profile

- Profile: paired-device plus iOS-specific paired-device.
- Boundary being proven: real Flutter/Go bridge request serialization, relay
  authenticated transport ACL, real encrypted blob custody, production
  SQLCipher save/reload/completion, real process/lifecycle recovery, receiver
  decrypt/hash/render, and UIApplication background-task behavior.
- Live availability check:
  `flutter devices --machine; adb devices -l; xcrun simctl list devices available`
  -> observed USB Pixel 6 `21071FDF600CSC` (Android 16/API 36), Android emulators
  `emulator-5554` (API 35) and `emulator-5556` (API 37), and USB iPhone 11
  `00008030-001A6D2801BB802E` (iOS 26.5). iPhone 13 is excluded. Re-run this
  command immediately before proof and pin only live IDs.
- Required setup: a non-empty real relay multiaddress in
  `MKNOON_RELAY_ADDRESSES`; centrally prepared
  `android.e2e.group_media_269` APK; dedicated
  harness package/DB names; fresh disposable recipient account plus an
  admitted/restored active receiver-device roster whose account peer ID differs
  from its transport peer ID (`deviceId` may equal transport); valid generated
  JPEG/MP4/voice/encryption/hash fixtures; automated permissions/navigation;
  compile-gated Android post-claim/pre-commit barrier with atomic host marker;
  sanitized per-role logs and criteria artifact directory. TC-269-20 also
  requires the centrally prepared/signed
  `build/sims/prepared/ios.device.group_media_269.bundle` passed as
  `SIMS_ARTIFACT_IOS_DEVICE_GROUP_MEDIA_269`, the dedicated Android companion
  passed as `SIMS_ARTIFACT_ANDROID_E2E_GROUP_MEDIA_269`, the canonical fixture
  driver, and explicit target-bound disposable-device authorization; its runner
  may not invoke a build.
- Two-peer default: USB Pixel `21071FDF600CSC` plus Android emulator
  `emulator-5554`, fully harness-driven. The iPhone 11 is used only for the
  separate iOS suspension boundary and explicit Android/iOS parity, not as the
  default second endpoint.
- Closure role: TC-269-19 is required production-critical closure evidence;
  TC-269-20 is required for the iOS receiver critical-task change while a USB
  iPhone is available. Exact unavailable hardware is N/A per project policy;
  the physical-only prepared bundle is never substituted onto a simulator, and
  the deterministic native suite still runs on an available simulator.
- `FLUTTER_DEVICE_ID`: host selector only for the transport gate; it is not
  sufficient for paired-device rows, which require both explicit `-d` IDs.
- Registration: `groups.media_send_reliability` in
  `tool/sims/critical_features.json`, literal families
  `group`,`media`,`transport`, `android.e2e.group_media_269` build profile with
  `build.android.e2e.group_media_269` dependency/read resource, exclusive physical
  Android/emulator/staging-relay and artifact-write resources, prepared-artifact
  target capabilities, artifact validator, exact runner/support discovery, and
  `classify_path` coverage. A separate dynamic registration contract proves
  each required full path appears exactly once inside `GROUP_TESTS`; global
  completeness alone is insufficient. The command emits one `SIMS_RESULT_JSON` with
  path/SHA-256/validator evidence and performs zero child builds. This manifest
  capability owns only TC-269-19; TC-269-20 remains a direct iOS proof.
- Discovery command:
  `dart run integration_test/scripts/run_group_media_send_reliability.dart --list-scenarios`
  -> lists exactly `group_media_foreground_retry_acl_roundtrip` and
  `group_media_ios_receiver_background_recovery`; plus
  `./scripts/check_reliability_simulation_discovery.sh` -> runner/support and
  manifest capability discovered exactly once.
- Closure commands:
  `./scripts/run_test_gates.sh sims major --prepare-builds --only groups.media_send_reliability`
  followed by
  `./scripts/run_test_gates.sh sims major --only groups.media_send_reliability`
  -> the first command centrally prepares the dedicated APK and the second
  registered capability consumes it with one audited artifact;
  `export SIMS_ARTIFACT_ANDROID_E2E_GROUP_MEDIA_269="$PWD/build/app/outputs/flutter-apk/app-debug.apk"; test -n "${MKNOON_RELAY_ADDRESSES:-}" && dart run integration_test/scripts/run_group_media_send_reliability.dart --scenario group_media_foreground_retry_acl_roundtrip -d 21071FDF600CSC,emulator-5554`
  -> three media kinds settle once end-to-end, host force-stop/fresh-PID proves
  the named JPEG resumes from durable `downloading`, same role DBs reopen at
  SQLCipher v104, and an explicitly invoked second gated pass does zero work;
  `./scripts/run_test_gates.sh sims major --prepare-builds --only build.ios.device.group_media_269`
  followed by
  `export SIMS_ARTIFACT_IOS_DEVICE_GROUP_MEDIA_269="$PWD/build/sims/prepared/ios.device.group_media_269.bundle" SIMS_ARTIFACT_ANDROID_E2E_GROUP_MEDIA_269="$PWD/build/app/outputs/flutter-apk/app-debug.apk" SIMS_GROUP_MEDIA_IOS_FIXTURE_DRIVER="$PWD/integration_test/scripts/group_media_ios_fixture_driver.dart" SIMS_GROUP_MEDIA_IOS_DEDICATED_DISPOSABLE_DEVICE=00008030-001A6D2801BB802E; test -n "${MKNOON_RELAY_ADDRESSES:-}" && dart run integration_test/scripts/run_group_media_send_reliability.dart --scenario group_media_ios_receiver_background_recovery -d 21071FDF600CSC,00008030-001A6D2801BB802E`
  -> while that USB iPhone is live, its RunnerUITests controller drives fast
  success plus actual Home/forced interruption/relaunch, discriminated terminal
  path, exactly-one native end, and one resume convergence. Native injected
  expiry/late-end exactness is the preceding RunnerTests gate.
- Deferred device work: no unavailable Android/iOS version or iPhone 13 leg is
  required. Additional hardware is optional confidence only.

## Acceptance Gates

```bash
# Baseline and live matrix; record unrelated dirty files and exact live IDs.
git status --short
flutter devices --machine
adb devices -l
xcrun simctl list devices available

# First causal RED before production edits; expect non-zero because null/0 is
# rejected while all other authority remains strict.
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field'

# W1 sender/persistence/lease/MIME focused GREEN; expect exit 0.
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 ordinary foreground media survives database-defaulted retry counters and reaches exact completion once'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 voice foreground media survives database-defaulted retry counters and reaches exact completion once'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'P269 exact group upload completion accepts omitted counters without SQL null'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'P269 exact group upload completion preserves local authority and accepts upload owned fields'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'P269 SQL default wrapper matches production schema for omitted and explicit null counters'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 successful incomplete-group recovery carries both persisted counters into completion and settles only once'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 completion persistence failures advance exact bounded sequence and discriminate lost authority'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 foreground completion failure projects bounded only while exact pending authority survives'
flutter test test/core/database/helpers/group_messages_db_helpers_sending_test.dart --plain-name 'P269 sending sweeper preserves parents with pending group uploads in both age modes'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 ordinary multi-media foreground lease owns every durable persisted blob ID until settlement'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 group composer canonicalizes heif to image heic and uploads and publishes once'

# W2 transport-identity ACL and fail-closed focused GREEN; expect exit 0.
flutter test test/features/groups/application/group_media_allowed_peers_test.dart --plain-name 'P269 group media ACL uses active device transport identities with revoked-safe legacy fallback'
flutter test test/features/groups/integration/group_media_fanout_test.dart --plain-name 'P269 group media fanout ACL never emits account or device IDs when transport IDs differ'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'P269 external group media share uses active transport ACL and never account or device IDs'
flutter test test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'batch invite reuploads existing avatar for expanded member ACL before signing invites'
flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name 'GCA-103 post-invite avatar upload includes late invitee in allowedPeers'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 ordinary and voice empty ACL preflight preserves sources with zero durable or crypto effects'
flutter test test/features/conversation/application/upload_media_use_case_test.dart --plain-name 'P269 explicit empty group ACL fails closed before encryption or bridge upload'
flutter test test/features/groups/application/group_avatar_storage_test.dart --plain-name 'P269 group avatar empty ACL fails before file access or bridge upload'
flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name 'P269 group avatar edit never falls back to account ID when member ACL is empty'

# W3 receiver/recovery/lifecycle focused GREEN; expect exit 0.
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name 'P269 ordinary group transient failure uses one atomic retry transition while relay authorization denial stays terminal'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'P269 group download failure CAS is atomic and deletion journal cannot resurrect media'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'P269 duplicate replay media enrichment starts exactly one canonical download without a second delivery side effect'
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'P269 detailed duplicate outcome reports exact persisted media across every dedupe branch'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'P269 recoverable group download query is authority scoped cursor paged and cannot starve later rows'
flutter test test/features/groups/application/retry_incomplete_group_downloads_use_case_test.dart --plain-name 'P269 group download recovery pages past denied rows and converges eligible durable media exactly once'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'P269 overlapping listener route and recovery sweep share one transfer and stop awaits tracked recovery'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P269 automatic route media recovery delegates to shared coordinator while explicit retry stays user owned'
flutter test test/core/lifecycle/handle_app_resumed_group_download_recovery_test.dart --plain-name 'P269 resume runs group media recovery after first group inbox drain'
flutter test test/core/services/pending_message_retrier_group_download_recovery_test.dart --plain-name 'P269 restored not ready and account denied do no work before node ready coalesced recovery'
flutter test test/features/groups/integration/group_media_reliability_wiring_test.dart --plain-name 'P269 every production group conversation invocation shares one gated download coordinator'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'P269 discussion and announcement media consult shared auto download policy immediately before transfer'

# W4 receiver background/native ownership host leg; expect exit 0.
flutter test test/features/groups/application/group_message_listener_media_background_task_test.dart --plain-name 'P269 background group media receive balances grant refusal success throw and stop wait'

# Exact sender/direct/private/membership preservation sentinels; expect exit 0.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'voice stop pre-persists a durable pending attachment and threads a stable blob ID'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'TC-15 group foreground lease defeats a full retry and the later winner releases after envelope settlement'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'PGC-010 action-first upload completion precedes B3 and blocks final send'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'PGC-010 B3-first membership phase stops incomplete upload dispatch'
flutter test test/features/conversation/application/upload_media_use_case_test.dart --plain-name '1:1 encrypted upload advertises opaque mime to the transport'
flutter test test/features/conversation/application/upload_media_use_case_test.dart --plain-name 'group upload still advertises the real mime to the relay'
flutter test test/core/media/group_media_mime_policy_test.dart

# Exact not-found/integrity/private preservation sentinels; expect exit 0.
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name 'relay not found short-circuits to download_failed without burning the retry budget (INV-DL-4)'
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name 'group policy deletes mismatched content hash bytes and does not mark done'
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name 'direct encrypted download stages to .enc, never promotes ciphertext to canonical'
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name 'terminal private parent denies before bridge or row mutation'
flutter test test/features/groups/integration/group_private_media_cleanup_replay_test.dart --plain-name 'group private explicit download commits only through current-parent guarded CAS'
flutter test test/features/groups/application/announcement_incoming_message_authorization_test.dart --plain-name 'APL-11 current non-admin announcement sender is rejected on live and offline receive before persistence'
flutter test test/features/groups/application/announcement_incoming_message_authorization_test.dart --plain-name 'APL-03 current announcement admin remains accepted on live and offline receive'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'group retrier never consumes same id direct pending media'
flutter test test/features/feed/presentation/screens/feed_wired_bg_task_test.dart --plain-name 'bg:begin happens before inline send transport and bg:end happens after success'

# Harness criteria, scenario discovery, and manifest/discovery registration.
flutter test test/features/groups/integration/group_media_reliability_criteria_test.dart
flutter test test/integration/group_media_reliability_runner_contract_test.dart
flutter test test/integration/ios_xctestrun_relocator_test.dart --plain-name 'P269 test without building accepts validated group media selector and preserves notification default'
bash scripts/test/group_media_reliability_group_gate_registration_contract_test.sh
bash scripts/test/reliability_simulation_discovery_contract_test.sh
dart run integration_test/scripts/run_group_media_send_reliability.dart --list-scenarios
./scripts/check_reliability_simulation_discovery.sh
./scripts/run_reliability_simulations.sh group --list --only integration_test/scripts/run_group_media_send_reliability.dart:group_media_foreground_retry_acl_roundtrip
./scripts/run_reliability_simulations.sh group --list --only integration_test/scripts/run_group_media_send_reliability.dart:group_media_ios_receiver_background_recovery
./scripts/run_test_gates.sh sims-contracts
./scripts/run_test_gates.sh completeness-check

# Relay security/compatibility sentinels; no Go authorization weakening.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^(TestGroupMediaUploadDownload|TestGroupMediaUnauthorizedPeer|TestBackwardCompat)$' -count=1)

# Causal native critical-task registry/expiration behavior. Re-resolve and set
# an available simulator ID before invoking xcodebuild.
export IOS_XCTEST_SIMULATOR_ID=674DFFF6-5F38-4235-93F6-AF7FBF86AE65
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$IOS_XCTEST_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/GoBridgeCriticalTaskTests

# Curated and justified preservation families; no per-plan full host-all.
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Registered prepared-build Android proof, then direct boundary reruns with
# fresh disposable identities. The runner emits one structured Sims result.
test -n "${MKNOON_RELAY_ADDRESSES:-}" && ./scripts/run_test_gates.sh sims major --prepare-builds --only groups.media_send_reliability
test -n "${MKNOON_RELAY_ADDRESSES:-}" && ./scripts/run_test_gates.sh sims major --only groups.media_send_reliability
export SIMS_ARTIFACT_ANDROID_E2E_GROUP_MEDIA_269="$PWD/build/app/outputs/flutter-apk/app-debug.apk"
test -n "${MKNOON_RELAY_ADDRESSES:-}" && dart run integration_test/scripts/run_group_media_send_reliability.dart --scenario group_media_foreground_retry_acl_roundtrip -d 21071FDF600CSC,emulator-5554
# Run the next three physical-only lines only when the pinned USB iPhone is
# present; otherwise record TC-269-20 physical leg N/A and keep the native
# simulator suite above as the required available boundary.
./scripts/run_test_gates.sh sims major --prepare-builds --only build.ios.device.group_media_269
export SIMS_ARTIFACT_IOS_DEVICE_GROUP_MEDIA_269="$PWD/build/sims/prepared/ios.device.group_media_269.bundle"
export SIMS_GROUP_MEDIA_IOS_FIXTURE_DRIVER="$PWD/integration_test/scripts/group_media_ios_fixture_driver.dart"
export SIMS_GROUP_MEDIA_IOS_DEDICATED_DISPOSABLE_DEVICE=00008030-001A6D2801BB802E
test -n "${MKNOON_RELAY_ADDRESSES:-}" && dart run integration_test/scripts/run_group_media_send_reliability.dart --scenario group_media_ios_receiver_background_recovery -d 21071FDF600CSC,00008030-001A6D2801BB802E

# Hygiene and graph refresh after one coherent app-owned change.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
git status --short
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-269-01 rejects the DB-equivalent `null/0` row on HEAD. The
  first production edit is forbidden until that assertion fails for the exact
  counter reason and still rejects every changed sibling authority field.
  TC-269-04's counters-present conflict leg independently REDs because HEAD
  overwrites `created_at`/`thumbnail_hash`; the SQL-null failure may not mask it.
- Green sentinel: ordinary pre-persist/finalize, voice stable ID, PGC-010
  action/B3 ordering, direct opaque MIME, group real MIME, exact Go unauthorized
  denial, not-found/integrity/private download outcomes, and native critical
  task tests all remain GREEN.
- Pre-existing dirty tree / known failure: the pre-planning unrelated baseline
  has
  `M docker-ws/run_fresh_three_phones.sh`,
  `M docker-ws/run_fresh_three_phones_result.txt`, and `M info.plist`; preserve
  them. The current review workspace additionally has modified `00-INDEX.md`
  and untracked plan/fixlist documents; execution may update this plan's
  progress only and must leave the index/fixlist untouched absent separate
  authority. The Pixel's captured SQL constraint/re-upload failure is expected
  HEAD evidence, not an accepted post-change failure.
- Environment blocker: none at planning time. Pixel, Android emulator, and
  iPhone 11 were live, and the app had relay connectivity. At execution, a
  missing exact version/model is N/A per project policy; use a currently
  available target. Missing all real-relay access blocks only device closure,
  not host implementation progress, and must be recorded rather than faked.
- Scope drift: any DB migration/new status, Go authorization relaxation,
  account-ID relay fallback, direct/private behavior change, unbounded retry,
  user-driven device step, production identity deletion, or edit to the dirty
  baseline blocks completion and requires replanning.

- [x] Every one of the 20 behaviors has its named test/proof and no empty
      contract cell.
- [ ] Each causal test is observed RED for the documented mechanism before its
      production edit, then GREEN; a representative mutation/revert makes its
      owning row red again. TC-269-20 did not turn GREEN, and a representative
      mutation/revert was not independently archived for every row.
- [x] Counter normalization is limited to local retry `null/0`; exact CAS,
      membership, owner, path, hash, and positive-count authority remain strict.
- [x] Every completion builder/boundary preserves expected creation time,
      thumbnail hash, and both counters while the explicit upload-owned size/
      path/hash/encryption changes still land; omitted/default and explicit-null
      fake behavior matches production-schema SQLite.
- [x] Completion failure follows exact counts/status `1/pending`, `2/pending`,
      `3/upload_failed`; successful retry drains once and later pass performs
      zero uploads/downloads/publications after that pass is explicitly invoked.
- [x] Empty ACL fails before ordinary/voice copy/save/source cleanup, shared
      crypto/bridge, and avatar file access; null direct/non-empty group remain
      GREEN; every scoped group-conversation share/avatar ACL contains only
      active transports and posts remain explicitly deferred.
- [x] Receiver failure status/count/path is one deletion-journal-aware CAS with
      zero resurrection or partial tuple; authorization/not-found/integrity stay
      truthful terminal outcomes, sibling files remain byte-identical, and the
      group lane sends no relay delete-ack.
- [x] Cursor paging reaches eligible rows beyond denied pages. Listener, route,
      resume, ready-restored, and periodic triggers use one policy-aware
      coordinator; early-not-ready/account-denied/private/terminal rows do not
      mutate.
- [x] All five duplicate exits are explicit: stable successful enrichment
      reports exact committed IDs and transfers once; identical/guard-refused/
      content-only paths transfer zero; no duplicate delivery side effects occur.
- [ ] Background receive records exactly one normal native end or deterministic
      injected expiry; refusal/throw/stop-waits and generic caller preservation
      pass. The single physical-device run did not prove final recovery from
      interruption, because its fresh process never published the final UI
      effect.
- [x] `GROUP_TESTS`, two legacy scenario expansions, prepared
      `android.e2e.group_media_269`
      capability/dependency/resources, artifact validator, and classification
      are registered once; the dynamic exact-membership contract, runner/Sims,
      and separate completeness classification contracts pass.
- [ ] Focused tests, exact relay/native sentinels, curated groups, pinned
      transport, justified feature/core family gates, and device artifacts pass
      with their semantic outcomes. Every listed non-TC20 gate passed, but the
      TC-269-20 device artifact did not, so the combined checkbox remains
      intentionally open.
- [ ] TC-269-19 proves prepared-main-app real-relay JPEG/MP4/voice on the
      Pixel/emulator, real force-stop/fresh-PID recovery, explicit-pass
      cardinality, and same-role SQLCipher cipher/v104/reopen rows; TC-269-20
      proves deterministic XCUITest Home/forced-interruption/relaunch on an
      available USB iPhone or is N/A by project policy. TC-269-19 passed;
      its final frozen-source registered proof is
      `0d7e4315…8d904`. TC-269-20 ran on an available target, failed the final
      UI-effect assertion, and was bypassed by explicit user instruction.
- [ ] W1 through W4 each have an Execution Progress evidence row and explicit
      GO decision; no wave proceeds on a red checkpoint. W4 has an explicit
      exception decision rather than its original GO.
- [x] No migration is added; DB remains v104.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean; the
      incremental Graphify refresh completed; unrelated dirty files remain
      untouched.
- [x] Scope Contract And Guard is respected.

## Handoff

- Plan status/classification: implementation complete / implemented with one
  unresolved device-proof exception, Bug, device closure, 20 contract rows.
- First causal RED command:
  `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field'`.
- Preservation command: `./scripts/run_test_gates.sh groups`, plus exact relay
  denial and pinned transport commands in Acceptance Gates.
- Manual registration: add shared upload/download/ACL/avatar and new group
  recovery/background/criteria/wiring/runner/relocator tests to `GROUP_TESTS`;
  the dynamic contract must find every `P269` path plus contact-picker exactly
  once inside that array. Register two legacy scenarios, Android main-app
  capability, dependency/resources/families, validator, and discovery/selector
  paths once. iOS stays a direct boundary.
- Fixtures: differential SQL-default wrapper; production-schema SQLite FFI with
  deletion journal/fault injection; paged policy candidates; fake
  relay/bridge/lifecycle/Swift task-manager seams; compile-gated Android barrier
  plus host PID controller; prepared main APK; fresh disposable identities with
  account != active transport; real relay and same reopened production
  SQLCipher role DBs only in device rows.
- Migration: none — current DB v104 columns are already `NOT NULL DEFAULT 0`.
- Boundary closure: the required Pixel + emulator real-relay
  force-stop/relaunch roundtrip passed TC-269-19 directly and through its
  registered Sims capability. After the final lifecycle fix, the registered
  capability passed again from current source digest `2ff0aa86…cb53` with
  proof `0d7e4315…8d904`, one prepared artifact, and zero child builds. A
  supported USB iPhone was available, so
  TC-269-20 is not N/A: its single capped run passed Phase A and the Phase B
  claim/termination boundary, but failed because the fresh process did not
  publish the final UI effect. The user directed that TC-269-20 be bypassed
  after that run. See `evidence/269/TC20-EXECUTION-NOTES.md`.
- Gate cadence: no per-plan full `host-all`; run it once after the Group Media
  Reliability 269 wave and once at final release closure.
- Confirmed findings: nullable counter/SQL exact-completion regression,
  unmasked creation-time/thumbnail overwrite, endless re-upload on persistence
  failure, unstable ordinary lease IDs, helper plus
  external-share ACL identity defects, empty-ACL and raw-avatar downgrade, HEIF
  rejection, duplicate-enrichment starvation, split failure-write resurrection,
  fixed-page starvation, Orbit/Feed route/readiness recovery bypasses, and
  missing/native-expiry-unsafe iOS receiver critical-task ownership.
- Refuted findings: receiver/iPhone/relay inbox/group membership did not cause
  the captured sender failure; relay uploads succeeded and publication never
  began. Receiver-only retry cannot converge an immutable stored relay ACL, so
  authorization denial remains immediately terminal. The later fixlist's group
  delete-ack, legacy-specific denial attribution, blanket row freeze, mandatory
  natural-expiry gate, and unavailable-hardware blocker are also refuted.
- Unresolved evidence: TC-269-19 resolved the sender, relay ACL, SQLCipher, and
  Android process-death claims. TC-269-20 alone remains unproven at its final
  physical-device cold-relaunch UI-effect assertion; host/native causal tests
  remain green, and no further device attempt is authorized by the user's
  one-run cap. No other unresolved production hypothesis is authorized.
- Review state: independent `$tdd-review` and the later 11-agent fixlist were
  critically re-verified on 2026-07-22. Only source-backed, non-duplicative
  deltas are incorporated; unsafe recommendations are recorded as rejected.
  Begin with the first RED; no further review prerequisite remains.

## Execution Progress

| Time | Phase | Files | Last command/result | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-22 13:57 CEST | W1 baseline + first REDs | `Test-Flight-Improv/evidence/269/sims/head-group-media-incident-sanitized.txt`; retry/completion tests and production seams | Pixel logcat excerpt SHA-256 `debbfc85a0d829e9951fb0a0a95bc5896dd121406a2e28a9a9084e2ad3c4982c`; TC-269-01 RED on `null != 0`; TC-269-04 RED on SQL `NULL` and local-field overwrite; TC-269-05 RED on dropped download counter | live Pixel/emulator pair and pinned iPhone/simulator resolved; focused counter/field fixes GREEN; W1 remains in progress | finish TC-269-02/03/06/07/10 RED→GREEN and W1 checkpoint |
| 2026-07-22 14:09 CEST | W1 sender persistence complete | TC-269-01..07/10 production and focused tests | All named W1 tests GREEN; exact ordinary/voice, TC-15, both PGC-010, direct/group MIME sentinels GREEN; `group_media_mime_policy_test.dart` 6/6; curated `groups` 2,830 Flutter tests plus bridge/node/relay Go gates GREEN | **GO W2** — counter normalization stayed limited to `null/0`, completion ownership and bounded failure are exact, durable IDs are leased before visibility, no migration | execute TC-269-08/09 RED→GREEN and W2 checkpoint |
| 2026-07-22 14:28 CEST | W2 transport ACL + fail-closed completion | TC-269-08/09 helper, fanout, share, composer, upload leaf, avatar, group-info, invite fixtures, and curated registration | Causal REDs captured for share account IDs, avatar direct downgrade/file-first validation, group-info account fallback, and ordinary durable work before empty-ACL rejection; every named W2 test GREEN; relay authorization/compatibility sentinel GREEN; curated `groups` 2,917 Flutter tests plus bridge/node/relay Go gates GREEN | **GO W3** — every scoped sender uses unique active transports with revoked-safe legacy fallback; explicit empty group ACL is terminal before claimed effects while null direct mode remains intact | author TC-269-11/12 REDs, implement atomic receiver failure persistence and detailed duplicate outcomes, then continue paged shared recovery |
| 2026-07-22 15:25 CEST | W3 receiver recovery + lifecycle complete | TC-269-11..16 atomic failure/automatic claim+commit CAS, detailed dedupe, durable query/coordinator, listener/routes/resume/retrier wiring, singleton source proof, and curated registration | Initial checkpoint audit STOP found dissolved-group mutation, post-selection claim/commit races, denied-prefix starvation, account-before-policy ordering, guard-refused quote write, and weak singleton proof; causal REDs captured and closed. Settled root exact suite 18/18 GREEN; 17 sender/direct/private/announcement/feed preservation sentinels GREEN; download 70/70, repository 49/49, handler 73/73, listener 211/211; scoped analyzer clean; curated `groups` 3,003 Flutter tests plus bridge/node/relay Go gates GREEN; corrected-tree `core-host-all` 347 paths / 2,731 tests GREEN | **GO W4** — automatic recovery is authority-complete and fair, explicit/private behavior remains isolated, duplicate enrichment is side-effect exact, and one coordinator owns every automatic route | author TC-269-17 Dart/native/shared-caller REDs, then TC-269-18 harness contracts before device work |
| 2026-07-23 12:57 CEST | W4 native/harness/device complete with exception | TC-269-17/18 native ownership, prepared-artifact custody, strict runner/criteria/registration contracts; TC-269-19 Android proof; TC-269-20 iOS proof | TC20-focused host suite 23/23 GREEN; Swift critical-task suite 7/7 GREEN; exact relay Go suite 3/3 GREEN. Prepared v15 Android/iOS artifacts share source digest `6914da96…47616`, with zero child builds. TC-269-19 direct proof `c1ba18d8…8defe` and registered proof `9cbd5c5…aba83c` PASS. The one allowed TC-269-20 run passed Phase A and Phase B claim/termination evidence but failed its final fresh-process UI-effect assertion after 4m21s | **ACCEPTED WITH EXPLICIT TC-269-20 EXCEPTION** — W4's original all-device GO condition is not met; the physical proof is FAIL, not N/A, and was bypassed only by the user's one-run instruction | finish isolated host/curated gates, analyzer/diff, sanitized closure evidence, and one incremental Graphify refresh; do not rerun TC-269-20 |
| 2026-07-23 13:40 CEST | Final allowed closure | final-source TC-269-19 registered proof; curated/family/native/transport gates; analyzer; sanitized evidence; Graphify | Current-source TC-269-19 proof `0d7e4315…8d904` PASS with artifact `33539970…ca8f`, no child build, three media kinds exactly once, zero second-pass work, and both SQLCipher role databases reopened at v104. Curated groups 3,305 GREEN; `feature-host-all` 824 paths / 8,555 pass / 1 skip GREEN; `core-host-all` 350 paths plus renderer contract GREEN; pinned transport 6 invocations / 21 tests GREEN; analyzer and diff checks clean; Graphify incremental refresh wrote 62,537 nodes / 94,456 edges | **CLOSED WITH EXPLICIT TC-269-20 EXCEPTION** — all authorized implementation and non-TC20 verification work is complete; the physical cold-relaunch UI-effect claim remains unproven and is not represented as PASS or N/A | retain sanitized closure summary and TC20 notes; no further TC-269-20 execution |
