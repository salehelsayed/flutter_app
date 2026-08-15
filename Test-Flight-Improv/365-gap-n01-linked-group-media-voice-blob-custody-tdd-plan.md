# 365 - GAP-N01 Linked-Group Media/Voice Per-Recipient Blob Custody

Status: IMPLEMENTATION_COMPLETE / HOST_VERIFIED / ANDROID SQLCIPHER VERIFIED / LIVE-ACCEPTANCE-BLOCKED / ADMISSION-DEFAULT-OFF / NOT RELEASE-ELIGIBLE
Type: Modification
Planning snapshot: `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c` before the in-flight Plan-364 implementation; Graphify `07f6a2a42e17060c` (`confidence=anchored`, `freshness=current` at query time); DB v114; canonical pre-Plan-364 `GROUP_TESTS` inventory 244/244
Execution baseline: implementation inherited the dirty Plan-364 worktree above rather than a clean post-execution audit commit. There is no clean Plan-364/365 audit SHA to claim; `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c` remains ancestry context, not an implementation or closure pin.
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; successor to Plans 363-364
Classification: implemented, default-off adopter for ordinary initial group image/GIF/video/audio/voice and per-final-recipient blob lifetime; host and Android SQLCipher proof are accepted, while live B1b acceptance, activation, release and GAP-N01 closure remain open
Closure tier: five causal host IDs, one DB-v115 real-SQLCipher upgrade leg, exact existing/new-kind Go custody proofs, the affected `groups`, `1to1` and `core-host-all` lanes once, and one availability-bounded extension of the existing Android B1b scenario

## Current Execution Closure — 2026-08-14

- Boundary: implementation is complete on the inherited dirty Plan-364 baseline. This is host closure, not a clean-tree post-execution audit; there is no clean audit SHA and no `PLAN-GREEN`, GAP-N01 closure or release-eligibility claim.
- Compact protocol correction: the first full signed-manifest projection serialized to **632,351 bytes** at the scoped maximum of **99 physical recipients x 10 attachments**, above the 128 KiB relay frame. The accepted representation serializes canonical `recipientPeerIds` once at manifest top level, stores each attachment's target expiries as a positional `expiresAtMs` array aligned to that list, and signs only the canonical manifest SHA-256 while carrying the hash-bound manifest once outside `signedPayload`. The same maximum envelope is **84,913 bytes**.
- Focused causal receipt: **29/29** actual TC-365 tests completed. The focused owner inventory includes `test/core/media/group_media_blob_artifact_store_test.dart`; the narrow linked owner is `test/features/groups/presentation/group_conversation_wired_test.dart`.
- Mutation receipt: all five planned semantic mutations were run serially, each produced its intended RED, and each was immediately reverted; the same five exact tests then passed GREEN. The mutations covered a direct-lane leak, network-before-stage, deletion of a referenced artifact, ACK-before-durable-commit and skipped incoming pause quiescence.
- Host receipts: affected `1to1` **3,185 passed / 10 skipped / 0 failed**; `core-host-all` **3,315 Flutter passed / 0 failed across 409 paths**, plus **2 manifest contracts**; completeness **1445/1445**; runtime roots **20/20**.
- Groups/registration receipt: the fresh post-compact `groups` gate passed **4,181 Flutter / 0 skipped / 0 failed**, plus **four Go package checks and the relay toolchain contract** (`/tmp/plan365_groups_postcompact.log`). Canonical `GROUP_TESTS` inventory is **245/245**, with `test/core/database/migrations/115_group_media_blob_custody_test.dart` registered exactly once.
- Android SQLCipher receipt: exact `TC-365-01a Android SQLCipher v114-to-v115 group media custody survives reopen` passed **+1**.
- Live acceptance: the exact B1b `--list` discovery/registration leg passed, but the paired live run was not executed. It remains blocked pending explicit S2 authorization to temporarily enable both default-off admissions, `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true` and `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=true`, followed by restoration to off.
- Graph/hygiene: after syntax cleanup, the final Graphify refresh is current/anchored at `bca7201d154029f0`: **75,164 nodes / 109,503 edges**, with a TDD overlay of **1,571 files / 15,610 named tests / 1,241 production targets**. The broad review was refined by exact anchors `StrictGroupMediaBlobDownloadAckOwner` and `PreparedGroupMediaBlobCustodyCoordinator`. Full analyze first returned **0 errors / 0 warnings / 2 infos**; both null-aware-map infos were fixed, targeted analysis and the sender TC-365 **2/2** passed, and the final full rerun passed with `No issues found!` in 27.2s (`/tmp/plan365_flutter_analyze_final2.log`). This remains execution evidence, not a clean audit SHA or audit-closure claim.

## Planning Progress

| Time | Role | Files inspected | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-08-13 | Evidence collector / planner | Graphify TDD context; Plans 363-364; group composer, share, sender, upload/download, retry, receive, lifecycle and UI owners | Plan 364 is being implemented in the shared worktree, so its envelope, transactional apply, restricted runtime, tests and inventory are moving. | Freeze only the successor contract. Author no Plan-365 RED until Plan 364 has a clean post-execution audit SHA and the exact extension seams are revalidated. |
| 2026-08-13 | Sender / custody review | `foreground_group_media_upload.dart`; `retry_incomplete_group_uploads_use_case.dart`; `send_group_message_use_case.dart`; legacy relay media and strict media custody | Current group uploads encrypt once but publish one shared `allowedPeers` blob; retry recomputes a mutable ACL. Any allowed peer can retire that legacy blob, so it cannot prove per-final-recipient lifetime. | Reuse the incumbent strict recipient-qualified media action/backend, add only a group-specific kind and group-owned durable projection, and never fall back from strict rows to `allowedPeers`. |
| 2026-08-13 | Storage review | DB v114 `direct_media_blob_custody`, its repository/model/artifact owners and v113-to-v114 SQLCipher proof | The v114 table and model are direct-only: direct owner columns, direct artifact root, direct kind and direct-only receive gate. Overloading a contact column with a group ID is invalid; schema-free closure is refuted. | Provisional DB v115 generalizes the incumbent table in place with an explicit owner lane and group owner, preserving all v111/v114 direct rows and APIs. Add no second blob ledger or refcount table. |
| 2026-08-13 | Receiver / lifecycle review | incoming group message persistence, media download/retry, P2P content ACK ordering, notification custody, cold/resume/pause | Current group receive writes event/message/attachments separately and downloads through proof-less legacy transport; it never ACKs group blobs. | Extend Plan 364's typed transaction for descriptor/custody/attention commit, ACK content after that commit, then independently download/decrypt/promote and source-pin the exact blob ACK. |
| 2026-08-13 | Runtime / UI review | restricted linked runtime; `GroupConversationScreen`; current full `GroupConversationWired`; B1b harness | Starting the broad group media runtime or full wired controller would also expose topic/history/private/settings paths. | Extend only Plan 364's restricted fixed point and narrow linked conversation owner. Reuse the pure screen with a capability-filtered ordinary media/voice surface. |
| 2026-08-13 | Test / gate economy review | current 244-path `GROUP_TESTS`; existing media/custody tests, Go tests, SQLCipher proof, DTR/runtime contracts and B1b runner | Five causal IDs cover the distinct schema, authoring, survivor, receive/download and runtime/UI boundaries. Existing files cover all but one v115 migration path. | Run independent Flutter files concurrently with `--concurrency=4` whenever possible. Run mutations, SQLCipher, curated lanes and shared devices serially by ownership. Do not run duplicate media campaigns or per-plan full `host-all`. |
| 2026-08-13 | Independent TDD review | Fresh current-source counterexample pass across sender/share/voice, v114 migration, strict media/inbox expiry, Plan-364 retry authority, Go commands and gate selection | Core direction is sound, but the draft allowed content to outlive blobs, one raw-sender demotion, early producer side effects, vacuous multi-file filters, impossible byte-identity wording and indistinguishable target receipts. | Apply the seven bounded corrections in this artifact; keep Plan 365 prerequisite-blocked. No product decision, extra protocol/backend or broad campaign is needed. |
| 2026-08-14 | Implementation closure | DB v115, group artifact/custody owners, compact manifest, authoring/retry/receive/runtime/UI seams, focused/curated/family gates and Android SQLCipher | Production and host boundaries are implemented and verified. Execution inherited the dirty Plan-364 baseline, so no clean audit SHA exists. Maximum-envelope redesign reduced 632,351 bytes to 84,913 bytes; final analyzer and Graphify receipts are green/current. | Keep both admissions default-off. Await explicit S2 before the live B1b run; make no audit, activation, GAP or release claim. |

## Problem And Evidence

- Behavior to improve: an ordinary primary or active linked secondary in a Plan-363/364-authorized group must be able to send and receive ordinary initial image, GIF, video, audio and voice content without a logical-account, mutable-roster, shared-blob or generic group-runtime downgrade.
- Impact: the current `allowedPeers` group blob is one shared deletion authority. One final recipient can remove the relay copy before its siblings obtain it, and a linked device cannot safely recover media through the restricted runtime.
- Original gap (now implemented under the strict selector): `runForegroundGroupUploadLeaf` and `retryIncompleteGroupUploads` resolved mutable `allowedPeers`; `uploadMedia` used the legacy group upload; `downloadMedia` routed strict custody only for `MediaOwnerLane.direct` and deliberately never ACKed group blobs.
- Confirmed reusable boundary: `go-relay-server/media_custody.go` already owns exact `(recipient,id)` storage, exact `stored|duplicate`, recipient-qualified download/ACK and ACK-or-expiry cleanup. Plan 365 adds a group kind to this action/backend; it adds no new action, native command, relay store, quota owner or scheduler.
- Original schema gap (now implemented and SQLCipher-verified): DB v114 constrained `direct_media_blob_custody` to `direct_media_blob_v1`, the direct artifact root, direct contact/key shape and direct-only repository APIs. DB v115 supplies honest group ownership and cross-lane isolation.
- Pre-implementation coverage: P269 group media tests proved legacy group upload/retry/download; Plan-362 proved direct strict recipient fanout and source-pinned ACK; Plan 364 supplied typed protected content application. Plan 365 now combines group authority, target-specific blob custody and linked restricted recovery in the focused receipt above.
- Previously missing coverage, now represented in the 29/29 focused inventory: durable attachment-by-physical-target rows; immutable target-specific blob commitments in protected content; restart survivor progress; atomic group descriptor/custody/attention commit; strict group download/ACK; restricted linked media runtime and UI.
- Refuted findings:
  - schema-free reuse of current group uploads is refuted because legacy `allowedPeers` is shared deletion authority;
  - a second group content kind/topic is unnecessary because media descriptors belong inside Plan 364's signed `group_content_v1` event;
  - a new relay action/backend or per-target ACK ledger is unnecessary because strict media custody already has exact recipient identity and durable ACK/expiry semantics.
- Resolved implementation seam: the inherited Plan-364 envelope/apply/runtime surfaces accepted the media projection. The initial repeated full target matrix overflowed the frame, so the implementation compacted recipients and expiries positionally and binds the single outer manifest with a signed SHA-256.
- Confirmed lifetime correction: strict media blobs expire from their earlier successful upload time, while protected content would otherwise expire from its later store time. Plan 365 must bound each target's content custody by the minimum expiry of that target's attachment commitments through the existing expiry-ceiling field; content may never outlive a referenced blob.

### Plausible production bypass inventory

- Fresh producers: ordinary composer attachments and voice in `group_conversation_wired.dart`; fresh external OS group share in `share_batch_delivery_coordinator.dart`.
- Retry producers: `retry_incomplete_group_uploads_use_case.dart`, `retry_failed_group_messages_use_case.dart`, lifecycle/network-restored/periodic composition roots.
- Receive/recovery: Plan-364 protected content replay, `group_message_listener_media_receive_coordinator.dart`, `retry_incomplete_group_downloads_use_case.dart`, resume/retrier callbacks.
- Adjacent but excluded: group avatar/config, forwarded/quoted/private/view-once/disappearing media, media caption EDIT/DFE, shared-media history, generic topic/cursor and legacy P269 device campaigns. Initialized strict authority must refuse these before a new send-owned durable write; uninitialized ordinary-primary groups retain incumbent legacy behavior.

## Graph Grounding Snapshots

- Graph fingerprint / freshness: `07f6a2a42e17060c`; anchored/current before Plan-364 production edits began. Treat it as planning evidence only.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 365 linked group media blob voice strict custody successor to Plan 364 groupContentV1: sendGroupMessage media attachments voice group blob custody lifecycle retry receive linked restricted runtime" --profile tdd --budget 700`.
- Anchor: `sendGroupMessage` surfaced through `test/shared/fakes/group_test_user.dart`; source verification then anchored `send_group_message_use_case.dart`, `foreground_group_media_upload.dart`, `retry_incomplete_group_uploads_use_case.dart`, `download_media_use_case.dart` and `media_custody.go`.
- Surfaced proof/gate files: group sender/upload/download/retry tests, direct media custody Go tests, migration tests, lifecycle tests and the B1b runner.
- Graph gaps requiring source search: the compact graph did not expose v114 CHECKs, strict relay keying, group share/voice callers or the direct-only download branch; all load-bearing claims above were checked in current source.
- Execution refresh: after syntax cleanup, the final incremental graph contains 75,164 nodes / 109,503 edges; the TDD overlay reports 1,571 files / 15,610 named tests / 1,241 production targets.
- Review query: the first result was broad, then an exact-anchor refinement on `StrictGroupMediaBlobDownloadAckOwner` and `PreparedGroupMediaBlobCustodyCoordinator` returned `confidence=anchored`, `freshness=current`, fingerprint `bca7201d154029f0`.
- Honesty boundary: `bca7201d154029f0` is current execution/navigation evidence, not a clean-tree audit or commit fingerprint. The old `07f6a2a42e17060c` remains planning-only.

## Scope Contract And Guard

In scope:

- Ordinary initial group image/GIF/video/audio attachments, voice (audio plus duration/waveform metadata), optional sanitized initial caption, and a fresh non-forwarded external OS share.
- Both an ordinary primary and active linked secondary when the Plan-364 strict authoring admission resolves initialized authority. Use Plan 364's selector/admission; add no third group selector.
- A single AES-GCM ciphertext artifact per attachment shared locally across exact physical-target obligations; each relay target still owns an independent strict blob copy and expiry.
- One protected `group_content_v1` logical event whose signed manifest binds the immutable full physical ACL and every target's exact attachment custody commitment.
- Outgoing survivor retry, incoming descriptor commit, strict download/decrypt/promote, exact ACK retry, artifact/reference cleanup, cold/resume/pause and the narrow linked media/voice UI.
- DB v115 and its real SQLCipher proof.

Must preserve:

- Every v111/v114 direct custody row, direct repository behavior, direct artifact root, direct wire kind and Plan-362 strict download/ACK -> `TC-365-01a` plus existing `TC-362-01a` and exact direct Go sentinels.
- Uninitialized ordinary-primary group media keeps the incumbent P269 `allowedPeers` route byte-equivalent; initialized strict authority never demotes to it -> `TC-365-02a`.
- Plan-364 blob-free message/reaction behavior and protected ACK ordering stay unchanged when no media manifest exists -> final accepted `TC-364-*` sentinels.
- Group private media remains safe-disabled for linked strict authority and incumbent legacy policy remains unchanged elsewhere -> existing private safe-disabled and transport boundary tests.
- Group avatar/config remains outside this content lane -> existing `group_avatar_storage_test.dart` and `group_info_wired_test.dart` authority sentinels.
- Group media remains relay-only and never enters the direct LAN leg -> `TD6` in `p2p_service_impl_lan_media_test.dart`.

Hard `Do not`:

- Do not add a second content envelope, media topic, relay backend/action, native command, per-target ACK table, refcount column, accepted ledger, scheduler, group selector or generic linked runtime.
- Prefer the one in-place v115 custody generalization. Do not add a second group custody table without stopping and re-reviewing an exhaustive direct-query qualification spike; an isolated table is only a fallback if the shared-table proof cannot safely qualify every incumbent direct owner.
- Do not reuse `contact_account_peer_id` as a group owner, infer targets on retry, re-encrypt after initial artifact persistence, or copy one target's relay expiry/proof to another.
- Do not ACK a content envelope before the exact descriptor/custody/notification transaction; do not ACK a blob before verified plaintext promotion plus exact durable ACK-pending state.
- Do not let a strict fingerprint/row fall through legacy upload, download, delete or failed-message rebuilding.
- Do not let a caller omit strict prepared-manifest authority and thereby make initialized media look legacy at raw `sendGroupMessage`.
- Do not expose private/view-once/disappearing, forwarded, quoted, avatar/history/shared-library, settings/info, media EDIT/DFE or broad group callbacks on the linked surface.

Deferred / accepted difference:

- Private/view-once/disappearing group media, forwarded/quoted group media, group avatar/history/no-intent, media caption EDIT/DFE and crash-complete general artifact erasure remain with the later residual code-closure/history plan. Initialized strict linked-group authority fails them closed; this plan does not certify them.
- Activation/cohort operations, mixed-version rollout, quota UX, legacy retirement, consolidated iOS and final GAP-N01/release closure remain WP-07/later closure work.
- No iOS-specific behavior changes. An iOS campaign is not required; platform-independent policy is host-tested, and unavailable device/API bands cannot block closure.

Dependencies:

- Implementation reused the inherited Plan-364 `group_content_v1` lane, physical ACL/survivor ownership, typed transactional apply outcomes, authority-version binding, restricted fixed-point runtime and narrow linked conversation surface. The planned clean post-execution-audit prerequisite was not satisfied, so this remains a documented baseline deviation and prevents audit closure.
- Plan 365 extends those APIs without replacing their authority, event identity, ACK or scheduler contracts.

## Storage And Wire Contract

- DB v115 rebuilds the incumbent `direct_media_blob_custody` table in place as the compatibility physical owner. Add explicit `owner_lane` (`direct|group`), nullable `group_id`, and a relay `custody_blob_id`; historical v111/v114 rows become `owner_lane=direct`, `group_id=NULL`, `custody_blob_id=attachment_id`. Their exact v114-column projection remains byte-for-byte equal; the deterministic new columns are asserted separately.
- Direct rows retain every v114 CHECK and partial-unique behavior. Group rows require nonblank `group_id`, null direct contact/key columns, `custody_kind=group_media_blob_v1`, `custody_contract=ack_or_expiry_v1`, and a lane-qualified artifact path. Lane participates in every exact unique index/key/CAS. Every incumbent direct loader, drain, cleanup, delete and retry query explicitly requires `owner_lane='direct'` before group rows are admitted; a direct owner can never observe or retire a group row.
- Add nullable `media_attachments.group_media_blob_custody_fingerprint`; historical rows remain null and are never promoted. It is a one-way no-demotion digest after custody rows retire. Do not overload the direct fingerprint/version.
- A group relay blob ID is a deterministic domain-separated value derived from group ID, message ID and attachment ID, within the existing relay ID grammar. The logical attachment ID remains the canonical UI/DB ID. The signed manifest exact-binds both.
- Reuse the existing media-custody actions and backend, but admit `group_media_blob_v1` under the same default-off media-custody admission. Kind, recipient and ID remain exact identity inputs; a group/direct crossed kind is an identity conflict, never a duplicate.
- Keep a separate group artifact root. One flush-close-rename-readback-verified ciphertext path may be referenced by N outgoing target rows; cleanup queries exact remaining references instead of persisting a refcount. This plan proves process-crash recovery, not sudden-power-loss directory durability, and does not claim a directory `fsync` the current Dart store cannot provide.
- The compact signed-hash-bound Plan-364 media manifest binds, in canonical attachment order: logical attachment ID, custody blob ID, ciphertext SHA-256/size, real MIME/media type, dimensions/duration, AES-GCM scheme/key/nonce and optional caption metadata. Canonical physical `recipientPeerIds` appear once at manifest top level; each attachment stores a positional `expiresAtMs` vector aligned to that list, while kind/contract appear once as manifest-wide invariants. Relay peer IDs and local paths remain local-only.
- Relay expiry can differ per recipient. Wait for every target's exact blob receipt before signing and persisting the final content envelope; never project one representative target's receipt across siblings.
- For each target, sign and persist `contentExpiresAtOrBeforeMs = min(target attachment expiries)`. Extend the existing media-expiry-bounded protected inbox capability to `group_content_v1` under the same action/backend/admission. Relay content storage must return exactly that expiry ceiling, reject an omitted/crossed/expired ceiling and never extend beyond the earliest referenced blob.
- The original repeated full target matrix measured 632,351 bytes at the scoped 99-recipient x 10-attachment maximum and was rejected. The compact top-level-recipient/positional-expiry representation measures 84,913 bytes for the same maximum, below the incumbent 128 KiB relay frame without reducing recipients or attachments.

## Authoring, Retry And Cleanup Contract

- Run Plan 364's read-only group/content admission after source/MIME/size/modality validation but before any new send-owned message/attachment row, durable copy, ciphertext artifact, crypto, background task, upload or content network effect. Picker/recorder source acquisition predates this boundary; refusal preserves that source/draft. Voice must admit before its current durable copy/parent save; a sole-group external share must admit before preprocessing/copy. A mixed-target share may preprocess once for another admitted target, but that does not authorize any refused group target.
- Under the shared group authority phase, freeze the exact physical ACL, logical actor, physical signer, authority version and key epoch. Exclude only the authoring transport and retain same-account sibling devices.
- Prepare each ciphertext once to a deterministic group staging path using flush-close-rename-readback verification, then one SQL transaction stages parent, attachments, no-demotion fingerprints/generation, exact per-(attachment,target) prepared custody rows and artifact ownership before any network. SQL refusal deletes the just-created artifact; a process-crash orphan is reconciled only against the lane-qualified DB inventory.
- Blob stores may run outside the authority phase. Exact-CAS each accepted target receipt into its row. A/B partial progress retries only durable survivors with the same bytes and blob ID; no roster/key/crypto rebuild and no generic failed-message route.
- Only after every attachment/target blob receipt exists may one transaction build/read back the exact signed Plan-364 envelope and arm its existing content survivor owner. Until then the parent is unmistakably queued by strict blob custody and cannot publish/store content.
- Raw `sendGroupMessage` is a second choke point: an initialized group media call without the exact one-shot prepared-manifest authority refuses before `_persistOutgoingMedia` and every bridge call. Only an explicitly uninitialized ordinary-primary group retains the incumbent legacy branch.
- Before envelope binding only, a group `outgoing_stored` row may exact-CAS-replace its relay proof/expiry using the same lane/group/message/attachment/recipient/blob ID/hash/size/kind/contract and identical bytes. This is a new v115 group-only transition; direct v114 stored-to-stored semantics remain unchanged. After binding, target ceilings and blob proofs are immutable: retries use persisted authority; a target that reaches its ceiling follows Plan 364's exact expired/terminal disposition and is never reminted.
- On each accepted or expired protected-content target, one SQL transaction exact-shrinks that Plan-364 content survivor and moves all of that target's group blob rows to cleanup-pending. The final target transaction retires the content owner and its blob references together. Only after the last exact local reference is gone may cleanup unlink the shared artifact; crash/CAS failure leaves the old survivor and rows retryable.
- The initialized strict route performs zero legacy `allowedPeers`, zero generic `group:sendReliable` and zero topic publish. Content delivery uses only Plan 364's protected per-target custody after all blob commitments are bound.
- Selector rollback blocks fresh authoring but drains committed blob/content rows flags-independently. Authority supersession uses Plan 364's typed terminal reconciliation; it never remints targets or bytes.
- Cancel/failure before content binding terminalizes local prepared rows and removes the shared artifact only after the final local row/reference is gone. Already stored relay blobs expire independently. After content binding, exact event/content authority owns delivery; this plan adds no unsend protocol.

## Receive, Download And Runtime Contract

- Plan 364's typed protected apply transaction validates the media manifest against the exact recipient/authority version, then atomically commits event evidence, parent, every attachment descriptor, every incoming group custody commitment, the group no-demotion fingerprint, unread and durable notification readiness/terminal suppression. Content ACK follows only `applied|exactDuplicate|terminalReject` with exact durable evidence; it does not wait for blob download or OS display.
- A reaction may apply after the canonical parent/descriptor transaction; media readiness is not a reaction prerequisite.
- Strict group download sends the exact custody blob ID, local transport recipient, hash/size/kind/contract/expiry and source relay proof. Verify ciphertext hash/size, AES-GCM decrypt, write and flush-close-rename-readback-verify the durable plaintext, then one exact transaction moves the attachment to ready and custody to ACK-pending with its source relay. Only then send source-pinned ACK. This is process-crash durability, not a claim of directory-sync power-loss durability.
- Crash after local commit retries ACK only. Exact duplicate content/download produces no second unread/notification. Hash, source, recipient, expiry, authority or manifest conflict is terminal/fail-closed and never invokes legacy download/delete.
- Delete-for-me before download records exact local terminal suppression before ACKing that device's blob. It cannot remove a sender artifact still referenced by another target, another attachment, or a pending content owner.
- Extend Plan 364's bounded fixed point: protected retrieve/stage -> bootstrap -> authority -> inbound content/manifest apply -> outgoing blob survivor drain -> newly eligible protected content drain -> incoming blob download/ACK drain -> notification/list/conversation refresh. Revisit prerequisites until no progress.
- Pause stops new strict media admission, cancels/quiesces transfers, awaits exact in-flight handlers and retains rows/artifacts/ACK-pending state. Do not start `GroupMessageListener` topics, generic group upload/download owners or `startLiveServices` for an active linked secondary.
- Extend only Plan 364's narrow linked conversation owner over `GroupConversationScreen`: ordinary attach/record/send, render/play and explicit retry. Every private/share/forward/quote/history/info/settings/delete-for-everyone/edit callback stays null or per-row ineligible. Authority change requalifies each action under the shared phase.

## Test Contract

The five IDs are behavior families, not a license for one unit test to stand in for production wiring. The same ID appears on the minimum independent owner tests named below. Parameterize MIME/role rows inside those tests; do not create a modality or authority cross-product.

| Case | Behavior | Named test / proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-365-01a | DB v115 lane-generalized custody: every legal v114 outgoing/incoming state preserves its exact old-column projection; deterministic new columns; legal group rows; lane/kind/path/index isolation; explicit direct-query qualification; group fingerprint; atomic stage/readback; upgrade rerun, wrong-key and downgrade refusal. | `115_group_media_blob_custody_test.dart::TC-365-01a v115 generalizes strict media custody without altering the v114 projection`; `media_attachments_db_helpers_test.dart::TC-365-01a group media custody stages and CASes one exact physical target`; `media_attachment_repository_impl_test.dart::TC-365-01a direct drains cannot observe or retire group custody`; `media_attachment_repository_impl_test.dart::TC-365-01a sole-group fresh custody stores secure references and compensates a refused SQL stage`; `media_attachment_repository_impl_test.dart::TC-365-01a group strict fingerprint refuses legacy fallback after custody retirement`; `direct_inbox_custody_outbox_sqlcipher_proof_test.dart::TC-365-01a Android SQLCipher v114-to-v115 group media custody survives reopen` | Host FFI migration/repository plus one real Android SQLCipher DB | Causal compile-clean RED: v115/table/repository APIs absent -> all legal v114 state families and group rows pass; device row is acceptance-only after GREEN. | Remove lane from a unique/CHECK/direct loader so a direct drain observes a group row -> host row red. | Focused c4 command below; new host path added once to post-Plan-364 `GROUP_TESTS` and auto-globs `core-host-all`; existing integration path stays exact-device registered. |
| TC-365-02a | Fresh ordinary image/GIF/video/audio/voice and non-forwarded external share: admission before producer effects, exact logical/physical authority, one artifact, frozen full physical ACL incl. same-account sibling, distinct A/B receipts/expiries, all rows before network, target-specific blob receipts plus content ceilings before protected content, raw-sender omission refuses, maximum supported manifest fits the incumbent frame, initialized exclusions all-zero, uninitialized primary legacy control. | `send_group_message_use_case_test.dart::TC-365-02a raw sender refuses initialized media without exact prepared manifest`; `send_group_message_use_case_test.dart::TC-365-02a maximum supported group media manifest fits the relay frame`; `upload_media_use_case_test.dart::TC-365-02a strict group upload stores exact recipient custody without allowedPeers`; `upload_media_use_case_test.dart::TC-365-02a strict group authoring preserves GIF video audio and voice descriptors across discussion and admin policy`; `upload_media_use_case_test.dart::TC-365-02a initialized forwarded private and quoted group media refuse before preprocessing`; `group_conversation_wired_test.dart::TC-365-02a composer and voice admit before durable group media effects`; `share_batch_delivery_coordinator_test.dart::TC-365-02a group share admission precedes preprocessing and excludes forwarded private or quoted media` | Host fakes with real temp files/artifact crypto; discussion/admin, sole-group and mixed-share rows | Causal RED: initialized paths still write/upload before admission or demote through omitted authority -> each owner sentinel fails independently. | Route initialized media through legacy `allowedPeers`, omit target expiry ceiling or issue network before stage -> red. | Focused c4; existing owner paths already in `GROUP_TESTS`. |
| TC-365-02b | A/B and multi-attachment survivor retry: A stored/B failed, restart, only B retried with identical bytes/blob ID; expired pre-content receipt refreshes exact bytes; persisted target content ceiling; no re-encrypt/roster rebuild/failed-message bypass; final-reference-only artifact cleanup; selector-off committed drain. | `group_media_blob_artifact_store_test.dart::TC-365-02b identity cleanup retains exact references and deletes group artifacts`; `group_media_blob_artifact_store_test.dart::TC-365-02b identity cleanup bounds regular blob and temp deletion`; `group_media_blob_artifact_store_test.dart::TC-365-02b identity cleanup ignores links malformed roots and non-artifacts`; `group_media_blob_artifact_store_test.dart::TC-365-02b identity cleanup rejects malformed or foreign reference inventories`; `retry_incomplete_group_uploads_use_case_test.dart::TC-365-02b strict group blob survivors reuse one durable artifact without roster recompute`; `retry_failed_group_messages_use_case_test.dart::TC-365-02b strict queued group media never enters fresh-message retry` | Host persistent fakes reconstructed over the same repository/artifact directory | Causal RED: current retry recomputes `allowedPeers` and has no per-target group custody -> survivor, artifact and bypass assertions fail. | Delete artifact after first target, rebuild ciphertext, or recompute a later content ceiling -> red. | Same sender/retry c4 bundle; the artifact-store owner is auto-globbed by `core-host-all`; existing group paths remain registered. |
| TC-365-03a | Protected receive exact-matches distinct A/B multi-attachment commitments and commits event+parent+descriptors+incoming custody+attention before content ACK; swapped target proof refuses before commit; strict blob verifies/decrypts/promotes before source-pinned ACK; ACK failure/restart, duplicate, delete-before-download, expiry and no-legacy-fallback converge; bounded voice/download fairness. | `p2p_service_inbox_ack_ordering_test.dart::TC-365-03a group media content ACK follows the descriptor transaction`; `download_media_use_case_test.dart::TC-365-03a strict group blob ACK follows durable plaintext`; `retry_incomplete_group_downloads_use_case_test.dart::TC-365-03a strict group blob ACK recovery is source pinned`; `delete_group_media_for_me_use_case_test.dart::TC-365-03a delete before download terminalizes only local blob custody` | Host SQL repositories, real temp files/crypto, fake exact relay | Causal RED: current writes are split and download is proof-less/no-ACK -> independent transaction, download and deletion sentinels fail. | ACK content/blob before its transaction, copy A's proof to B, or let a fingerprinted row call legacy download -> red. | Focused c4; existing paths registered or run exact. |
| TC-365-04a | Restricted linked cold/resume/pause order, flags-independent drains, no broad topic/runtime; narrow attach/voice/view/retry revokes on authority drift; image+voice B1b reaches sibling and survives reopen. | `production_application_bootstrap_phase_contract_test.dart::TC-365-04a linked restricted runtime owns only strict group media`; `handle_app_resumed_upload_ordering_test.dart::TC-365-04a linked resume reaches a strict group content and blob fixed point before refresh`; `handle_app_resumed_group_download_recovery_test.dart::TC-365-04a linked resume routes strict group downloads before refresh without a generic owner`; `handle_app_paused_group_test.dart::TC-365-04a pause quiesces strict group media and resumes only the exact lease`; `group_conversation_screen_test.dart::TC-365-04a linked group exposes only ordinary media and voice`; `group_conversation_wired_test.dart::TC-365-04a linked group exposes only ordinary media and voice`; `invite_reliability_runner_contract_test.dart::TC-365-04a B1b registers group media and voice before terminal dissolve` | Host composition/lifecycle/widget plus paired physical-Android/emulator acceptance | Causal RED: no restricted group-media callbacks/UI exist -> each host boundary fails; device row is acceptance-only after host GREEN and authorized deployment. | Start a generic group media owner/topic or return from pause before quiescence -> red. | Focused c4, DTR/runtime roots, curated groups; B1b `--list` is closed, while live execution remains S2-blocked. |

### Test Notes

- TC-365-01a seeds every legal v114 direct state family, including cleanup and incoming ACK-pending, upgrades to v115, compares the exact v114-column projection, separately asserts deterministic v115 columns, inserts two group target rows, closes/reopens/reruns migration and tests wrong key plus v115-to-v114 downgrade refusal. It does not seed an impossible v114 group row.
- TC-365-02a parameterizes modality and discussion/admin policy inside one test. Host coverage owns video/GIF/multi-attachment; the device journey needs only one deterministic JPEG and one deterministic voice artifact.
- TC-365-02a pins the actual supported group-member, physical-device and attachment maxima. Its first repeated target-matrix projection measured 632,351 bytes and correctly forced redesign; the accepted compact projection measures 84,913 bytes and remains below the 128 KiB frame without a reduced-recipient fallback.
- TC-365-02a/03a use distinct relay IDs and expiries for A/B across at least two attachments. Swapping one target commitment must refuse before descriptor commit/content ACK; equal fake receipts are forbidden.
- TC-365-03a discriminates content ACK from blob ACK: descriptor commit permits the former; verified durable plaintext permits the latter. A wrong implementation cannot pass by ACKing both together.

## Implementation Contract And Outcome

Steps 2-8 below are implemented and verified by the receipts in the current closure section. Step 1's clean Plan-364 audit baseline was not obtained; that inherited-dirty-baseline deviation remains open and prevents audit closure.

1. Snapshot `git status --short`; finish and audit Plan 364. Commit a clean post-execution audit SHA and Graphify snapshot. Revalidate its envelope manifest extension point, transaction helper, strict retry owner, runtime/quiesce callbacks, narrow linked UI and final groups inventory. Repin this plan before RED.
2. Add the named owner-level TC-365-01a through TC-365-04a sentinels and SQLCipher assertion before production edits. Add only the v115 registration/type scaffolding needed for compile-clean semantic RED; an absent test or missing import is not a RED receipt.
3. First enumerate every direct-table helper/repository/drain/delete/retry query and add the TC-365-01a direct-vs-group isolation spike. If all can be exhaustively lane-qualified, implement DB v115 as one atomic rebuild/generalization plus group fingerprint, lane-qualified indexes/helpers/models and group artifact store. Stop and re-review—rather than forcing either design—if safe qualification would destabilize direct APIs or if an atomic copy/drop/rename cannot preserve every v114 projection.
4. Add `group_media_blob_v1` to the existing node/bridge/relay strict media custody parser and stored-row reparse under the existing action/backend/admission. Extend the existing protected inbox expiry-ceiling capability from direct media text to `group_content_v1`. Stop-if: a new action/backend/native binding or separate admission flag is required.
5. Add one shared Plan-365 group media coordinator consumed by composer, voice, fresh external share and incomplete-upload retry. Stage exact artifacts/rows before network, converge target receipts, then atomically arm Plan 364 content. Strict queued rows never enter generic failed-message reauthoring.
6. Extend Plan 364's signed manifest and transactional apply for target-specific group blob commitments. Add strict incoming download/ACK and delete/cleanup transitions; preserve its blob-free path byte-equivalent.
7. Wire one group-media drain/quiesce phase into the restricted cold/resume/pause owner and enable only the narrow media/voice callbacks in the linked group screen.
8. Reach focused GREEN using concurrent bundles where supported, run five mutations serially/reverted, exact Go and preservation proofs, one curated groups, one curated `1to1` and one core-host-all lane, SQLCipher/device boundaries when available, hygiene and one incremental Graphify refresh.

## Representative Mutations

Run exactly five production mutations serially after GREEN and revert each before the next:

1. Remove `owner_lane='direct'` from one incumbent loader/drain (or one v115 unique/CHECK) so a direct owner observes a group row -> TC-365-01a RED.
2. Route initialized strict group media through `allowedPeers` or perform the first network call before atomic custody stage -> TC-365-02a RED.
3. Delete the shared ciphertext after the first accepted target instead of the final local reference -> TC-365-02b RED.
4. Send content/blob ACK before its exact durable descriptor/plaintext transaction -> TC-365-03a RED.
5. Start the generic group media runtime for a linked secondary or skip pause quiescence -> TC-365-04a RED.

Do not count syntax errors, test-only mutations or alternatives in one run. Record the exact changed selector, failing semantic assertion and clean revert for each.

## Risks And Blind Spots

- Per-target relay expiries differ -> signed target-to-attachment commitment matrix and all-receipt barrier in TC-365-02a.
- Content stored after blobs could outlive them -> persisted per-target minimum-blob expiry ceiling and exact Go/host tests in TC-365-02a/02b.
- Shared local artifact vs independent target rows -> restart/final-reference mutation in TC-365-02b; no refcount cache.
- Split SQL/file durability -> deterministic staging path, flush-close-rename-readback, exact SQL ownership and orphan reconciliation; process-crash cuts in TC-365-02b/03a. Sudden-power-loss directory durability is not claimed.
- Descriptor ACK vs blob ACK confusion -> explicit two-event discriminator in TC-365-03a.
- Current group retry recomputes ACL and current failed-message retry can remint -> strict fingerprint and durable lane discriminator in TC-365-02b.
- Deletion/cancel can erase shared state -> exact preserved/removed row/file assertions in TC-365-02b/03a.
- Authority/selector change during crypto/network -> freeze under Plan 364 phase, recheck before content arm, typed terminal disposition; TC-365-02a/02b.
- Sibling surfaces -> composer, voice, fresh external share, incomplete retry and receive/retry are all in the shared coordinator or explicitly refused.
- Migration/downgrade -> v114-to-v115 real SQLCipher, idempotent reopen and downgrade refusal in TC-365-01a.
- Live relay/default-off admissions -> host work may proceed after Plan 364; device acceptance/activation may not.

## Gate Cadence

- Per-plan closure: four focused concurrency-4 Flutter bundles, one deduplicated focused c4 run, five serial mutations, exact Go media-custody proofs, DTR/runtime/completeness contracts as triggered, curated `groups` once, curated `1to1` once, and `core-host-all` once because v115 changes shared direct custody production code.
- Independent Flutter files must run concurrently with `--concurrency=4` whenever the runner supports it to speed feedback. Serialize only mutations, script-owned curated/family gates, SQLCipher and shared-device scenarios.
- Do not run feature-host-all, performance, transport, the old P269 device campaign, iOS, or full `host-all` for this individual plan.
- Run full `host-all` once after the remaining GAP-N01 group-content/history dependency wave is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs run by the exact commands below; registration under later `host-all` does not create another per-plan obligation.

## Acceptance Gates

### Historical clean-baseline preflight — not satisfied by this execution

The reviewed contract required a clean Plan-364 audit pin. Implementation instead inherited the dirty Plan-364 worktree, so this preflight was not passed and its unresolved base placeholder is retained only as deviation evidence; it is not a closure command or a claimed SHA. The measured post-implementation group-path count is 245.

```bash
set -euo pipefail
PLAN365_ACCEPTED_BASE='<PLAN_364_POST_EXECUTION_AUDIT_SHA>'
PLAN365_EXPECTED_GROUP_PATHS='245'
case "$PLAN365_ACCEPTED_BASE" in *'<'*|*'>'*) exit 1 ;; esac
case "$PLAN365_EXPECTED_GROUP_PATHS" in ''|*[!0-9]*) exit 1 ;; esac
test "$(git rev-parse "$PLAN365_ACCEPTED_BASE^{commit}")" = "$PLAN365_ACCEPTED_BASE"
git merge-base --is-ancestor "$PLAN365_ACCEPTED_BASE" HEAD
test -z "$(git status --porcelain)"
test -z "$(git diff --name-only "$PLAN365_ACCEPTED_BASE"..HEAD | \
  rg -v '^(Test-Flight-Improv/(364-gap-n01-linked-group-blob-free-content-custody-tdd-plan|365-gap-n01-linked-group-media-voice-blob-custody-tdd-plan|00-INDEX)\.md|STATUS\.md)$')"
python3 - "$PLAN365_EXPECTED_GROUP_PATHS" <<'PY'
import re
import sys
from pathlib import Path

text = Path('scripts/run_test_gates.sh').read_text()
match = re.search(
    r'^readonly GROUP_TESTS=\(\s*\n(?P<body>.*?)^\)\s*$',
    text,
    re.MULTILINE | re.DOTALL,
)
assert match is not None, 'GROUP_TESTS array not found'
block = match.group('body')
paths = re.findall(r'^\s*"([^"]+\.dart)"\s*$', block, re.MULTILINE)
expected = int(sys.argv[1])
assert len(paths) == expected, (len(paths), expected)
assert len(paths) == len(set(paths)), 'duplicate GROUP_TESTS path'
assert all(Path(path).is_file() for path in paths), 'missing GROUP_TESTS path'
print(f'GROUP_TESTS {len(paths)}/{len(set(paths))} unique')
PY
```

### Causal RED/GREEN bundles

Run independent files concurrently where possible. Before production edits, each command must select its named TC-365 test and fail for the documented missing behavior—not for compilation, setup or an unrelated assertion. After implementation, expect exit 0 and zero skipped TC-365 rows.

```bash
# B1: v115 storage and direct preservation
flutter test --concurrency=4 \
  test/core/database/migrations/115_group_media_blob_custody_test.dart \
  test/core/database/migrations/114_direct_linked_device_media_blob_fanout_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --name 'TC-365-01a|TC-362-01a'

# B2: fresh authoring plus durable survivor retry
flutter test --concurrency=4 \
  test/core/media/group_media_blob_artifact_store_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart \
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  test/features/conversation/application/upload_media_use_case_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --name 'TC-365-02a|TC-365-02b'

# B3: protected apply, strict download and ACK recovery
flutter test --concurrency=4 \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/features/groups/application/retry_incomplete_group_downloads_use_case_test.dart \
  test/features/groups/application/delete_group_media_for_me_use_case_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  --name 'TC-365-03a'

# B4: restricted runtime/UI and runner contract
PLAN365_NARROW_OWNER_TEST='test/features/groups/presentation/group_conversation_wired_test.dart'
case "$PLAN365_NARROW_OWNER_TEST" in *'<'*|*'>'*) exit 1 ;; esac
test -f "$PLAN365_NARROW_OWNER_TEST"
flutter test --concurrency=4 \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_resumed_group_download_recovery_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  "$PLAN365_NARROW_OWNER_TEST" \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-365-04a'
```

After all five mutations are reverted, run one deduplicated focused proof and reject vacuous selection/skips:

```bash
set -euo pipefail
PLAN365_NARROW_OWNER_TEST='test/features/groups/presentation/group_conversation_wired_test.dart'
PLAN365_NARROW_OWNER_SENTINEL='TC-365-04a linked group exposes only ordinary media and voice'
case "$PLAN365_NARROW_OWNER_TEST" in *'<'*|*'>'*) exit 1 ;; esac
case "$PLAN365_NARROW_OWNER_SENTINEL" in *'<'*|*'>'*) exit 1 ;; esac
test -f "$PLAN365_NARROW_OWNER_TEST"
test -n "$PLAN365_NARROW_OWNER_SENTINEL"
plan365_log="$(mktemp)"
trap 'rm -f "$plan365_log"' EXIT
flutter test --concurrency=4 \
  test/core/database/migrations/115_group_media_blob_custody_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_resumed_group_download_recovery_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/core/media/group_media_blob_artifact_store_test.dart \
  test/features/conversation/application/upload_media_use_case_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart \
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_downloads_use_case_test.dart \
  test/features/groups/application/delete_group_media_for_me_use_case_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  "$PLAN365_NARROW_OWNER_TEST" \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-365-01a|TC-365-02a|TC-365-02b|TC-365-03a|TC-365-04a' \
  --reporter expanded | tee "$plan365_log"
while IFS= read -r sentinel; do
  rg -Fq -- "$sentinel" "$plan365_log"
done <<'SENTINELS'
v115 generalizes strict media custody without altering the v114 projection
group media custody stages and CASes one exact physical target
direct drains cannot observe or retire group custody
sole-group fresh custody stores secure references and compensates a refused SQL stage
group strict fingerprint refuses legacy fallback after custody retirement
raw sender refuses initialized media without exact prepared manifest
maximum supported group media manifest fits the relay frame
strict group upload stores exact recipient custody without allowedPeers
strict group authoring preserves GIF video audio and voice descriptors across discussion and admin policy
initialized forwarded private and quoted group media refuse before preprocessing
composer and voice admit before durable group media effects
group share admission precedes preprocessing and excludes forwarded private or quoted media
identity cleanup retains exact references and deletes group artifacts
identity cleanup bounds regular blob and temp deletion
identity cleanup ignores links malformed roots and non-artifacts
identity cleanup rejects malformed or foreign reference inventories
strict group blob survivors reuse one durable artifact without roster recompute
strict queued group media never enters fresh-message retry
group media content ACK follows the descriptor transaction
strict group blob ACK follows durable plaintext
strict group blob ACK recovery is source pinned
delete before download terminalizes only local blob custody
linked restricted runtime owns only strict group media
linked resume reaches a strict group content and blob fixed point before refresh
linked resume routes strict group downloads before refresh without a generic owner
pause quiesces strict group media and resumes only the exact lease
linked group exposes only ordinary media and voice
B1b registers group media and voice before terminal dissolve
SENTINELS
rg -Fq -- "$PLAN365_NARROW_OWNER_SENTINEL" "$plan365_log"
if rg '~[0-9]+:.*TC-365-' "$plan365_log" >/dev/null; then exit 1; fi
```

### Exact Go, registration and preservation

The additive group kind changes parser identity but reuses the existing action/backend. Add one causal test in each existing owner; do not add a new Go package or gate tail. The new node/bridge/relay rows must use distinct A/B blob IDs and expiries, prove the target-specific content-expiry ceiling, and reject an omitted or swapped ceiling without disturbing the incumbent direct kind.

```bash
set -euo pipefail
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestTC365GroupMediaBlobCustody$' -count=1 -v | rg --fixed-strings -- '--- PASS: TestTC365GroupMediaBlobCustody (')
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestTC365GroupMediaBlobCustody$' -count=1 -v | rg --fixed-strings -- '--- PASS: TestTC365GroupMediaBlobCustody (')
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_GroupMediaBlobCustody$' -count=1 -v | rg --fixed-strings -- '--- PASS: TestRelayNotificationClosure_GroupMediaBlobCustody (')
```

Extend the post-Plan-364 `run_group_forwarding_go_bridge_gate` selector once with `TC365`; the relay test is already selected by `^TestRelayNotificationClosure_`. Use `-list` in the rollout contract to prove both new node/bridge tests and the relay prefix are registered; a comment-only `TC365` occurrence does not count. The canonical `1to1` gate below already owns the incumbent bridge/node/relay media-custody preservation and rollout shell, so do not duplicate those exact commands here.

Run only affected preservation/contracts and lanes:

```bash
set -euo pipefail
flutter test --concurrency=4 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
```

DTR is required only if its frozen application/bootstrap/adapter surfaces change; that is expected here. `runtime-roots` is required because the restricted runtime gains a media owner. `completeness-check` runs once because one host path and Go registration are added. Script-owned `groups`, `1to1` and `core-host-all` each run once; `1to1` is required because in-place v115 touches its direct production custody owner, not as a substitute for focused proof.

### Device/Relay Proof Profile

- Profile: one real Android SQLCipher leg plus one paired-device B1b extension.
- Boundary: encrypted v114-to-v115 migration/reopen and real physical-recipient group content+blob custody/ACK across process, relay and app restart.
- Live availability: resolve at execution with `flutter devices --machine` and `adb devices -l`; never bake historical IDs into the plan.
- Two-peer default: one discovered USB physical Android first plus one Android emulator second, fully automated by the existing B1b runner. No iPhone, third phone or manual taps.
- Deployment prerequisites: reader-first binaries containing Plan 364 plus `group_media_blob_v1`; separate explicit S2 authorization to temporarily set both `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true` and `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=true`; restore both to off immediately after B1b and record the rollback receipt.
- Device scope: one deterministic JPEG and one deterministic voice artifact before the existing reopen/terminal authority. Host tests own GIF/video/multi-target failure matrices; do not rerun the old P269 campaign.
- If an Android target/pair is absent, record `N/A (target unavailable by project policy)` for that leg; do not wait for an unavailable model/API band or substitute iOS.

```bash
set -euo pipefail
flutter devices --machine
adb devices -l
PLAN365_SQLCIPHER_ANDROID_ID='<AVAILABLE_ANDROID_ID>'
PLAN365_PHYSICAL_ANDROID_ID='<USB_ANDROID_ID>'
PLAN365_EMULATOR_ANDROID_ID='<ANDROID_EMULATOR_ID>'
test "$PLAN365_SQLCIPHER_ANDROID_ID" != '<AVAILABLE_ANDROID_ID>'
test "$PLAN365_PHYSICAL_ANDROID_ID" != '<USB_ANDROID_ID>'
test "$PLAN365_EMULATOR_ANDROID_ID" != '<ANDROID_EMULATOR_ID>'

flutter test -d "$PLAN365_SQLCIPHER_ANDROID_ID" \
  integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart \
  --plain-name 'TC-365-01a Android SQLCipher v114-to-v115 group media custody survives reopen'

RELIABILITY_MULTI_DEVICE_IDS="$PLAN365_PHYSICAL_ANDROID_ID,$PLAN365_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
RELIABILITY_MULTI_DEVICE_IDS="$PLAN365_PHYSICAL_ANDROID_ID,$PLAN365_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
```

### Hygiene and Graphify

```bash
set -euo pipefail
plan365_base_ref='<PLAN_364_POST_EXECUTION_AUDIT_SHA>'
case "$plan365_base_ref" in *'<'*|*'>'*) exit 1 ;; esac
flutter analyze
plan365_dart_list="$(mktemp)"
plan365_go_list="$(mktemp)"
plan365_gofmt_out="$(mktemp)"
trap 'rm -f "$plan365_dart_list" "$plan365_go_list" "$plan365_gofmt_out"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan365_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan365_dart_list"
if test -s "$plan365_dart_list"; then xargs dart format --output=none --set-exit-if-changed < "$plan365_dart_list"; fi
{
  git diff --name-only --diff-filter=ACMR "$plan365_base_ref"...HEAD -- '*.go'
  git diff --name-only --diff-filter=ACMR -- '*.go'
  git diff --cached --name-only --diff-filter=ACMR -- '*.go'
  git ls-files --others --exclude-standard -- '*.go'
} | sort -u > "$plan365_go_list"
if test -s "$plan365_go_list"; then
  xargs gofmt -l < "$plan365_go_list" > "$plan365_gofmt_out"
  test ! -s "$plan365_gofmt_out"
fi
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  "Review Plan 365 linked group media voice per-recipient blob custody after implementation; exact v115 lane isolation, Plan 364 manifest binding, survivor retry, receive ACK order, restricted runtime and necessary gates" \
  --profile review --budget 800 --ensure-fresh
```

## Execution Interpretation And Done Criteria

- Recorded RED: all five planned semantic mutations produced their intended causal failure and were immediately reverted; the same five exact tests then returned GREEN.
- Host sentinel: initialized strict authority uses only exact physical blob/content custody; uninitialized ordinary-primary behavior and every direct v114 row remain unchanged across the accepted focused and lane receipts.
- Baseline limitation: execution inherited the dirty Plan-364 worktree. It did not pass the reviewed clean-SHA prerequisite, and neither `3865aa9b...` nor the current Graphify fingerprint is a clean implementation/audit pin.
- Live blocker: default-off production admissions block device acceptance/activation, not host or SQLCipher verification. The available B1b topology was discovered, but the exact run requires explicit S2 for both admissions and therefore is blocked, not N/A.
- Scope guard: no new action/backend/table family/scheduler/selector, broad linked runtime or private/history/avatar adoption entered this closure.

- [ ] Clean Plan-364/365 audit baseline and clean closure SHA — **not satisfied; inherited dirty baseline recorded**.
- [x] Every behavior has a named causal test or exact boundary proof; focused TC-365 inventory is 29/29.
- [x] Five semantic mutation REDs were recorded, reverted and followed by five exact GREEN tests.
- [x] DB v115 preserves direct ownership, admits lane-qualified group rows and passes the exact Android SQLCipher upgrade/reopen proof (+1).
- [x] Exact group-kind Go package checks and the relay toolchain contract pass without a new action/backend/tail.
- [x] Strict media/voice authoring, survivor retry, receive/download/ACK and restricted runtime/UI pass with no legacy fallback.
- [x] Migration registration is exactly once; `GROUP_TESTS` 245/245, completeness 1445/1445, runtime roots 20/20, groups 4,181/0/0, affected `1to1` 3,185/10/0 and `core-host-all` 3,315/0 across 409 paths plus two manifest contracts pass.
- [ ] Availability-bounded Android B1b execution — **blocked pending explicit S2**; `--list` registration only has passed and both admissions remain off.
- [x] Final full analyzer rerun reports `No issues found!`; Graphify is current/anchored at `bca7201d154029f0`.
- [x] No activation, private/history/avatar, iOS, full-host, GAP-N01, audit-closure or release claim is made.

## Handoff

- Implementation handoff: the DB-v115 lane generalization, compact protected manifest, strict group producer/retry/receive/download/ACK owners, cleanup, restricted runtime and narrow linked UI are implemented and host-verified on the inherited dirty Plan-364 baseline.
- Accepted preservation: exact direct-v114/Go tests, final Plan-364 sentinels, private/avatar/TD6 sentinels, curated `groups`, affected `1to1`, justified `core-host-all`, SQLCipher and the five mutation proofs are recorded above and do not need repetition for this execution receipt.
- Remaining acceptance action: obtain explicit S2, temporarily enable both named default-off admissions, run the already-registered Pixel-6 plus Android-emulator B1b scenario, then restore both admissions to off and record the result. Until then the plan remains live-acceptance-blocked.
- Audit boundary: no clean Plan-364/365 post-execution audit SHA exists because implementation inherited the dirty baseline. A later audit may establish such a pin; this receipt does not infer one.
- Successor work: activation/operations, quota UX, mixed-version rollout, legacy retirement, excluded private/history/avatar surfaces, consolidated iOS confidence and final GAP-N01/release closure remain out of scope.

## Reviewer Findings

Execution verdict: **IMPLEMENTATION_COMPLETE / HOST_VERIFIED / ANDROID SQLCIPHER VERIFIED / LIVE-ACCEPTANCE-BLOCKED / ADMISSION-DEFAULT-OFF / NOT RELEASE-ELIGIBLE**. The core bet was confirmed in production: one v115 lane generalization plus the incumbent strict recipient-qualified relay primitive closes the host slice without a second backend, action, ledger or scheduler. The independent post-implementation review found and closed the proof-remint, outgoing cleanup/orphan and stage-refusal artifact counterexamples; the relay-frame counterexample forced the compact manifest correction from 632,351 to 84,913 bytes.

The numbered findings below are the historical pre-execution contract review. They remain useful design provenance, but their old prerequisite/wait disposition is superseded by the execution verdict above.

The independent review ran a fresh current-source counterexample pass and the review-profile Graphify query. That query was broad/stale on the in-flight Plan-364 tree, which confirms rather than relaxes the mandatory clean-audit requery. Fifteen required plan fixes were applied:

1. Bound every target's protected content expiry to its earliest referenced blob expiry through the existing expiry-ceiling capability.
2. Replace one-label/many-file theater with minimum independent owner sentinels and exact final-log selection.
3. Make raw `sendGroupMessage` refuse initialized media that omits exact prepared-manifest authority.
4. Move voice/share admission before their current durable/preprocessing effects and add sole-/mixed-target causal rows.
5. Fix the three `rg` PASS pipelines with `--` before dash-leading patterns.
6. Define migration preservation as exact v114 projection plus deterministic v115 columns across all legal state families.
7. Give A/B and multi-attachment fakes distinct IDs/expiries and require a swapped-target refusal before descriptor commit/ACK.
8. Limit stored-proof replacement to the pre-content-arm phase, then retire content survivors and target blob references atomically so cleanup cannot outrun delivery.
9. Require an exhaustive direct-query qualification spike, lane-qualified keys/CAS/queries, the affected curated `1to1` lane, and a stop/re-review fallback if safe in-place generalization cannot be proven.
10. State the actual flush-close-rename-readback process-crash boundary without claiming directory-`fsync` sudden-power-loss durability.
11. Remove zero-selection files from filtered bundles and require exact direct-isolation, upload, dynamic narrow-owner and B1b runner sentinels in the final log.
12. Match standard Go PASS lines including their duration suffix instead of requiring an impossible fixed whole line.
13. Fold a maximum supported member/device/attachment serialized-size assertion into TC-365-02a so the 128 KiB stop is causal.
14. Use the canonical `run_test_gates.sh 1to1` inventory and let its existing media-custody tails replace duplicate incumbent Go commands.
15. Require the repinned dynamic narrow-owner path to exist and its exact sentinel to be nonempty before either focused command can pass.

Five-lens execution result: L1 evidence truth `clear` for host and SQLCipher receipts, with the dirty-baseline/no-clean-SHA limitation explicit; L2 causality `clear` through independent producer/receiver owner sentinels and five mutation REDs; L3 bypass/scope `clear` with raw-sender admission and exhaustive direct-lane qualification; L4 executable host gates `clear`, while live B1b remains S2-blocked; L5 persistence/reversibility `clear` with atomic survivor/reference cleanup and real SQLCipher retained.

Blind-spot sweep: B-1 migration/downgrade, B-2 producer/retry/lifecycle bypass, B-4 vacuity, B-5 atomic cleanup/concurrency, B-6 durable fingerprints, B-8 real relay/device and B-9 excluded-surface preservation are explicit contract rows. B-3/B-7 are clear after current-source verification and the hard Plan-364 revalidation stop. B-10 is N/A because no iOS/cross-platform parity claim is made. No user-owned design decision remains.

## Arbiter Decision

`IMPLEMENTATION_COMPLETE / HOST_VERIFIED / ANDROID SQLCIPHER VERIFIED / LIVE-ACCEPTANCE-BLOCKED / ADMISSION-DEFAULT-OFF / NOT RELEASE-ELIGIBLE` is the honest state. Host implementation may be handed off; it is not `PLAN-GREEN`, a clean post-execution audit, activation, GAP-N01 closure or release closure. The only remaining Plan-365 acceptance leg is the explicitly authorized B1b run with both admissions temporarily enabled and restored off afterward.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision / blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-13 | historical planning snapshot | Plan artifact only | planning query and source verification | contract drafted against pre-Plan-364 snapshot | Plan 364 implementation/audit was in flight | superseded by the 2026-08-14 execution row below |
| 2026-08-14 | host implementation complete | DB v115; group custody/artifact, content, producer/retry/download/runtime/UI and Go relay/native owners; focused, migration, lifecycle and registration tests | TC-365 29/29; groups 4,181/0/0; 1to1 3,185/10/0; core-host-all 3,315/0 across 409 paths; completeness 1445/1445; runtime roots 20/20; five mutations RED/reverted/GREEN; Android SQLCipher +1; full analyze zero issues; Graphify `bca7201d154029f0` current/anchored | implementation and host/SQLCipher proof complete on inherited dirty baseline; admissions remain off | live B1b requires explicit S2; no clean audit, activation, GAP or release claim | obtain S2, run registered Pixel-6/emulator B1b, restore admissions off, then record live verdict |
