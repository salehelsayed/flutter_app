# 362 - GAP-N01 Direct Linked-Device Media, Voice, And Blob Fanout

Status: CODE-COMPLETE (executed 2026-08-12) / default-off authoring / three recorded deviations (private-parent DFE fanout, producer UI route wiring, device-pair harness program) / not release-eligible
Type: Modification
Planning baseline: `c78c465a027da7ff8586712ce0c9e6f7162f3ab8` (clean Plan-361 post-execution audit-hygiene closure; implementation `be897336d60f94c742fa04cb9933d90886489265`, receipt closure `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; immediate consumer of Plan 361's linked-device blob-free event fanout
Classification: DB-v114 direct one-to-one media/voice/blob fanout adopter plus a bounded relay internal-key repair; no group/announcement, activation, release, or GAP-N01 closure claim
Closure tier: focused concurrent host behavior, v114 migration and Move preservation, two exact Go relay tests, one existing Android SQLCipher proof, one aggregate physical-Android + Android-emulator event/blob scenario, and the single delegated Plan-360-to-362 dependency-wave `host-all`

## Planning Progress

| Time | Role | Evidence inspected | Decision / blocker | Disposition |
|---|---|---|---|---|
| 2026-08-11 | Evidence collector / planner | Graphify TDD context; active Plan-361 v113 scaffold; v108/v109/v111 schemas and helpers; media sender, retry, receive, lifecycle, download, Move, relay, fixture and runner owners | Plan 361 is actively changing the shared tree, so its final SHA and exact APIs do not yet exist. The current graph is useful for design only, not a closure pin. | Plan now, but block every RED until Plan 361 has a clean post-execution audit SHA and one final source/Graphify revalidation. |
| 2026-08-11 | Storage / lineage review | v111 attachment-only primary key and helper lookups; v108 completion; media-attachment lineage fingerprint; shared artifact cleanup; migration manifest builder | One canonical attachment must own several physical-recipient blob obligations. A second blob table, synthetic row ID or per-target attachment ID would duplicate natural authority, while one target-specific expiry fingerprint cannot describe every sibling. | Rebuild only incumbent v111 at DB v114, use exact `(attachment, direction, recipient)` row identity with partial uniqueness, share one encrypted artifact, and version the persisted attachment fingerprint so fanout uses one target-independent generation digest. |
| 2026-08-11 | Relay / lifecycle review | `go-relay-server/media_custody.go` disk paths, in-memory maps, reconciliation, upload/download/ACK/expiry and legacy collision fence | Disk is already recipient-scoped, but four in-memory maps are keyed only by attachment ID, so two recipients cannot safely own the same canonical ID. | Key those maps by `(recipientPeerId, attachmentId)` without changing the wire/action/native API; preserve the global legacy/protected ID fence and per-recipient quotas. |
| 2026-08-11 | Product / alternate-path review | Composer, voice, external share, received-media forward, failed/incomplete/unacked retry, caption EDIT, DFE, private eligibility, receive/download and restricted linked runtime | The smallest honest adopter includes every current direct blob producer, but modality coverage can be parameterized. Caption EDIT/DFE reuse Plan 361 v109 and never upload a new blob. | Include ordinary image/video/GIF/audio/file, voice, exact P/VO/disappearing shapes and every current producer; keep current unsupported combinations and private EDIT refused. |
| 2026-08-11 | Test / gate review | Existing TC-345/347/348/350/351/353/354/358/359 sentinels; migration/SQLCipher/Move owners; Android pair runner; relay shell contracts; project wave cadence | One new host test path, six compact behavioral rows, four mutations, two exact Go tests, one SQLCipher leg and one aggregate Android pair are sufficient. Plan 361 deliberately delegated the wave device composition and one full `host-all` here. | Run independent multi-file Flutter tests concurrently at `--concurrency=4` whenever supported; serialize only worktree mutations, script-owned `1to1`, SQLCipher and shared-device scenarios. |
| 2026-08-11 | Independent TDD review | Storage counterexamples, relay cross-recipient restart, fingerprint ambiguity, retry/remint, shared-file unlink, Move duplication, mixed-version/runtime paths and literal commands | Plan 361's selector is expressly blob-free and the existing media-custody flag may already govern single-target cohorts; shipping the new adopter behind only their intersection could activate linked media on upgrade. One separate default-off linked-media authoring selector is necessary, while a second ledger, accepted state, target-set hash, per-target media encryption, linked LAN path, modality matrix and extra device campaign are not. | `PREREQUISITE_BLOCKED / CONTRACT_READY`; retain the one narrow new selector and only the bounded production/proof surface below. |
| 2026-08-11 | Final formal re-review | Natural v111 row identity, linked incoming discriminator, P/VO null-lineage controls, unbound whole-generation terminalization, all four relay maps/transient fences, linked-origin device topology, 170-row ceiling, non-vacuous selectors and wave parity | Storage/relay, product/runtime and gate-economy reviewers independently returned READY after bounded amendments. No extra test ID, table, state machine, device or family gate was needed. | Keep `PREREQUISITE_BLOCKED / CONTRACT_READY`; only Plan 361's clean audit SHA/API/Graph pin remains. |
| 2026-08-12 | Final Plan-361 closure and successor revalidation | Plan-361 implementation `be897336d60f94c742fa04cb9933d90886489265`, receipts `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`, audit-hygiene closure `c78c465a027da7ff8586712ce0c9e6f7162f3ab8`; current anchored Graphify review `488091ffcb7bae21` (71,897 nodes / 105,515 links); live gate inventories and every Plan-362 path/sentinel | v113 generation authority, deterministic persisted-contact target snapshots, reverse transport authorization, serialized contact purge, restricted runtime, and plural survivor/retry guards match this contract. Current inventories are 123 one-to-one, 406 core Dart, 842 feature Dart, and 1,342 host-all Dart plus 8 Go. No executable prerequisite defect or test expansion was found. | Prerequisite satisfied. Mark `EXECUTION_READY`, pin the audit-hygiene SHA, and retain the reviewed necessary-only concurrent cadence. |

## Execution Progress

| Time | Step | Evidence | Result / next action |
|---|---|---|---|
| 2026-08-11 | Planning and independent review | Anchored Graphify planning query plus direct source verification; current Plan-361 worktree and generated graph are dirty by design | Contract ready for its blocked state. After Plan 361 closes, pin its already-refreshed committed graph/audit SHA, query/review once without refreshing, revalidate exact APIs/counts, and only then author compile-clean semantic REDs. |
| 2026-08-12 | Prerequisite unblock | Plan-361 audit-hygiene closure `c78c465a027da7ff8586712ce0c9e6f7162f3ab8`; Graphify `488091ffcb7bae21`; source/API, path, sentinel and dry-run inventory review | `EXECUTION_READY`. First action is the literal clean-tree/ancestry preflight, then the four concurrent host RED bundles plus the exact Go RED. |
| 2026-08-12 | Preflight + storage/relay execution | Literal clean-tree/ancestry preflight PASSED at the pinned base; v114 migration/model/helpers, fingerprint v2, relay `(recipient,id)` rekey | Go RED recorded first (both exact tests failed semantically on the ID-keyed relay: sibling admission conflicted, every fanout-isolation subtest red), then GREEN after the composite-key repair; full relay suite `-race` green; curated prefix now 12 and both `NR == 12` pins repinned. New v114 migration test green (fresh+rebuild+identity+rollback+downgrade); 111/113/full-chain/schema-inventory pins moved to v114; Move builder dedupes the exact shared `(path,hash,size)` artifact and refuses `crossed_duplicate_custody_proof`. |
| 2026-08-12 | Contract-script reconciliation | `relay_media_custody_contract_test.sh`, `reliability_simulation_discovery_contract_test.sh`, `direct_media_blob_custody_prebuilt_runner_contract_test.sh` | Schema-owner allowlist repinned for the v114 migration DDL and the shared SQLCipher discovery label extended (342/345/347/361/362): both green. The prebuilt-runner contract fails IDENTICALLY at the accepted Plan-361 baseline in a clean detached worktree (`adapter exited 64` on this host), so it is recorded as pre-existing environment parity, not a Plan-362 failure. |
| 2026-08-12 | Execution receipts (close) | Four c4 bundles, final proof, mutations, curated/wave/device gates, hygiene | Bundles: B1 `--name TC-362-01a` +3, B2 `TC-362-02a\|02b` +11, B3 `TC-362-03a` +4 (anchored `--name` substituted for the illustrative plain-name; coverage identical), B4 `TC-362-04a\|05b` +6 — all green after honest REDs (Go RED recorded pre-implementation; caption-EDIT RED exposed and fixed a real missing `allowDirectAttachments`). Final focused c4 proof `+39` exit 0 on the final formatted tree with all six TC-362 ids present and no skips. 4/4 causal mutations re-red and reverted (collapse-all-N insert; message-wide completion; relay ID-only rekey; in-transaction reverse-reauth bypass — the last only after an initially surviving variant exposed a test gap closed with a new reauth micro-test, Plan-360-style). Go: curated prefix 12 listed, both exact tests PASS `-race`, full relay suite green; both `NR == 12` pins repinned. Shell: relay + discovery contracts PASS after repins; prebuilt-runner contract fails IDENTICALLY at the accepted baseline in a clean worktree (pre-existing host-env parity). completeness 1441/1441. Curated `1to1` PASS 124/124 (123→124 as forecast). Wave `host-all`: 1343 Dart paths c4 failures-only `+13995 ~11 -16` with 8/8 Go tails PASS; of the 16, six were Plan-362 pin fallout (migration_database_active_importer ×5, runtime-root DTR-10 anchor) fixed and re-proven green per-file, and the residual ten (nine `test/integration` notification/PiP/iOS-provider/live-direct/relay-degradation plus one l10n literal census) reproduce EXACTLY (`-9`/`-1`) at the accepted Plan-361 baseline in a clean detached worktree — closure by exact path/outcome parity; full `host-all` was not rerun. v114 pin sweep also closed migrations 100–112 test fallout (version/user_version/registry tail-offset/census-map repins incl. one pre-existing duplicate row in the 104 chain). TC-362-05a PASSED on a real Android SQLCipher target (emulator-5554, exit 0): v113 legacy row preserved byte-identically through the v114 rebuild, two same-attachment target rows admitted with the exact-duplicate refused, reopen/rerun idempotent, wrong-key and v113 downgrade refused. DTR-18 repinned (placement media adapter body; layering application_root/bootstrap normalized digests) with adjacent Plan-362 rationale, 7/7 green. Analyzer clean, 77 changed Dart files format-clean, gofmt clean, all three diff checks clean, one incremental Graphify refresh on the final tree (review query current at fingerprint `693a8313f3c5ab7f`). Coverage/gaps doc records the Plan-362 receipt with GAP-N01/activation/release left open. |
| 2026-08-12 | Deviation record | v109 mutation-fanout media enablement; device-pair scenario surfaces | Two bounded deviations recorded for follow-up instead of silent scope creep: (1) PRIVATE-parent (P/VO/disappearing) DELETE-for-everyone still routes through the incumbent single-target private deletion lane — only ORDINARY-parent caption EDIT/DFE fan out through v109 in this execution; (2) the `direct_linked_device_event_blob_fanout` scenario is fully registered host-side (contract consts, physical-first pair parse, runner selector triple, TC-362-05b green) but the on-device harness program is not yet implemented, so the physical pair leg cannot run and the harness's unregistered-scenario guard fails closed. Both keep GAP-N01/activation honest and open. |

## Problem And Source-Backed Evidence

- Plan 361 pluralizes blob-free v108/v109 event custody and deliberately leaves every media/voice/v111 path, media caption mutation, media DFE, aggregate event/blob device proof and dependency-wave `host-all` to this plan.
- DB v111 stores `attachment_id` as the sole primary key. Its public model and helpers load, transition and delete by attachment alone, and outgoing completion assumes one recipient/incarnation. Multiple physical targets therefore cannot be represented by a caller loop.
- The encrypted media artifact is generation-wide: every target must receive identical blob bytes and content hash, while its relay namespace, expiry, recipient ML-KEM key and v108 envelope are target-specific. Minting per-target attachment IDs or encrypting the media file once per device would create false canonical media generations.
- `media_attachments.direct_media_blob_custody_fingerprint` currently commits target-specific expiry. Different target expiries cannot all equal one attachment value. Fanout needs an explicit fingerprint version whose v2 digest commits only the immutable blob generation; legacy/null retains the incumbent exact target-commitment meaning.
- Relay media disk paths already use `recipient/id`, but `entries`, `reservations`, `blocked` and `ackCleanupPending` are keyed only by ID. Reconciliation, upload, ACK and expiry can therefore conflict with or delete another recipient's same-ID custody.
- Current cleanup unlinks the encrypted file while retiring one v111 row. Under fanout, target A could destroy target B's retry source. Exact-row retirement and last-reference unlink must be one serialized decision under the incumbent lifecycle owner.
- External OS share and received-media forward are independent production producers, and ordinary FILE is a real blob path. Failed and incomplete upload retries can also bypass a composer-only fanout coordinator. Each must consume the same persisted target snapshot rather than grow its own loop.
- Account Move copies v111 and builds a file manifest from custody attachment IDs. Two target rows sharing one canonical file must preserve both rows while exporting/importing that file exactly once; crossed path/proof duplicates must refuse.
- Incoming linked media keeps physical transport identity as authentication/receipt route while persisting the logical account as canonical conversation identity. Plan 361's reverse authority must be requalified inside the message + attachment + incoming-v111 transaction.

Revalidated expected production surface:

- `app_database_version.dart`, `production_migration_registry.dart`, one `114_direct_linked_device_media_blob_fanout.dart` migration, one default-off direct-linked-media authoring flag, the incumbent v111 model/helper and the media-attachment fingerprint model/helper
- the incumbent v108/v109 generation/completion helpers and Plan-361 target snapshot/reverse-authority APIs; no new roster or event outbox
- `prepared_direct_media_blob_custody_coordinator.dart`, media attachment repository adapter, v111 drain/cleanup owner, and the smallest shared target-batch coordinator needed by send/retry callers
- chat-media, voice, external-share/forward, failed/incomplete/unacked retry, caption EDIT and DFE owners
- incoming chat/deletion, strict download/source-pinned ACK, private/disappearing lifecycle and final contact-delete owners
- Account Move file-manifest/bundle owners only where the shared-path preservation case requires them
- restricted linked cold/resume/pause/bootstrap and the smallest media/voice UI capability gate
- `go-relay-server/media_custody.go`, its existing direct-media test and recipient-aware device fixture probe; no relay wire/action, `go-mknoon`, Dart bridge, generated binding or native-platform change
- existing reliability runner/harness/parser/discovery contracts, including the stale SQLCipher discovery description in `scripts/check_reliability_simulation_discovery.sh`; no second harness or APK

Stop and re-review before adding a parallel blob table, per-target attachment identity, accepted-row ledger, target-set hash, refcount table, scheduler, new relay action/field, Dart/native bridge command, linked LAN routing, history/contact hydration, push/provider wake, group/announcement/post/feed behavior, or an unlisted durable authority.

## Graph Grounding Snapshot

- Graph: `graphify-arch`; the planning query was anchored. An incremental refresh occurred while Plan 361 was actively dirty, producing diagnostic fingerprint `21e26ca138e6146e`; it is not a committed-tree closure pin and must not be copied into the baseline.
- Final prerequisite review: current anchored fingerprint `488091ffcb7bae21` (71,897 nodes / 105,515 links) over Plan-361 implementation `be897336d60f94c742fa04cb9933d90886489265`, receipts `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`, and docs-only audit-hygiene closure `c78c465a027da7ff8586712ce0c9e6f7162f3ab8`.
- Planning query: `python3 graphify-arch/tdd_context.py query "Plan 362 GAP-N01 direct linked-device media voice v111 blob fanout after Plan 361 v113 event fanout; direct_media_blob_custody, direct_inbox_custody_outbox v108, media attachments, send media voice protected view-once disappearing, retry download receive cleanup, per-device target roster, relay ACK and Android pair gates" --profile tdd --budget 700`.
- Final unblock completed: the focused review query returned current/anchored, and the v113 target snapshot, reverse authority, contact purge and restricted-runtime APIs were revalidated without another code-graph refresh. No source or gate amendment was required.

## Scope Contract

### Prerequisite and rollout authority

- Author RED only from `c78c465a027da7ff8586712ce0c9e6f7162f3ab8` or a descendant whose only intervening files are this plan/index/status documentation, after the literal clean-tree/ancestry preflight below. The final Plan-361 API/Graphify review returned READY.
- Add one default-off `MKNOON_ENABLE_DIRECT_LINKED_MEDIA_FANOUT` injectable authoring selector. New linked blob authoring requires it together with Plan 361's `MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT` and `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED`. The Plan-361 switch explicitly owns blob-free batches, while the incumbent media flag may already be on for single-target strict custody; neither may silently activate this new adopter.
- Primary + uninitialized roster preserves the incumbent single-target path, including its LAN acceleration. Initialized roster + any required selector OFF refuses before media crypto, file write, upload, target-envelope crypto or message network and never demotes to one target.
- Already-committed v114/v108 rows, incoming strict custody and cleanup/download/ACK drain regardless of later selector rollback. Flags gate new authoring only.
- This is controlled upgraded-pair code closure, not authenticated version negotiation or general activation. Old receivers reject linked outer-physical/inner-logical traffic; old senders still reach only the legacy target.

### DB v114 and immutable media generation

- Rebuild only `direct_media_blob_custody`; do not add a synthetic row ID. Keep canonical `attachment_id` non-unique and use the natural exact identity `(attachment_id, direction, recipient_peer_id)`, with `IS NULL` for incoming.
- Enforce one outgoing row per `(attachment_id, recipient_peer_id)` and one incoming row per `attachment_id` through explicit partial unique indexes. Add no FK to messages, attachments, contacts or roster. Every historical row retains its exact columns and gains no inferred fanout authority.
- Add nullable `contact_account_peer_id` and `recipient_ml_kem_public_key`. Every newly authored LINKED outgoing or incoming row requires a nonblank logical contact. Outgoing additionally requires physical `recipient_peer_id`, persisted recipient ML-KEM key and the complete immutable blob proof; the dynamic legacy-primary target may have `recipient_peer_id == contact_account_peer_id`, while verified linked targets use a distinct transport. Linked incoming keeps `recipient_peer_id` and recipient key null. Historical/single-target rows keep all new columns null, and the DB must not impose a blanket recipient/account inequality.
- Make every v111 API direction- and target-explicit through that natural identity. A generic attachment lookup may return a list only; it must never select an arbitrary sibling.
- Add nullable `media_attachments.direct_media_blob_custody_fingerprint_version`. Null retains the existing target-specific digest contract. Version `2` is sender-local OUTGOING ordinary/disappearing lineage: the existing fingerprint column holds the target-independent digest of attachment ID, custody kind/contract, content hash, ciphertext size and transport MIME; per-target relay/expiry/recipient facts are excluded. Outgoing Protected/View-Once remains fingerprint+version null on its no-v110 private generation lane. Every incoming strict attachment remains exact target-specific with version null. Null/value/version contradictions refuse.
- Before any selector, capacity, resolver or crypto decision, query current-generation v108/v114 survivors. A survivor is the complete pending set and retries exact bytes only; zero survivors plus the matching durable Plan-361 generation is terminal and cannot remint. Only a genuinely new generation resolves a target snapshot.
- A newly authored generation encrypts and persists each attachment artifact once. In one transaction, requalify the persisted nonblocked contact and exact Plan-361 target snapshot/fingerprints, then stage all `targets x attachments` prepared v114 rows AND the durable Plan-361 initial-generation marker or none. The marker exists before upload/v108, survives terminal cleanup, and prevents remint if an unbound generation later cancels/expires. No blob or message network starts first.
- Upload identical canonical blob bytes under the same attachment ID separately to every persisted physical target. Record each target's exact relay/expiry without consulting the roster again. Only after every target manifest is live may the owner compute that target's exact manifest hash/earliest expiry, encrypt its v108 envelope with the persisted target ML-KEM key, mint one distinct incarnation, and atomically stage/bind the complete v108 batch. Cross-target manifests/expiries never substitute. The canonical message keeps Plan 361's generation witness using the stable first physical recipient in persisted peer order; that witness is correlation only and never retry/network authority, so no representative bit is added.
- First accepted ordinary/disappearing target completion may stamp the attachment's v2 generation fingerprint; later target completions must agree. P/VO completions retain the exact null-fingerprint invariant and rely on the Plan-361 generation plus surviving v114 authority. Completion transitions only that target's v111 rows. A nonfinal target leaves canonical message/lifecycle projection unchanged; only the final exact sibling may project the generation, and delivered/later state never downgrades.
- Existing rows are survivor-first retry authority. Restart, failure, revoke or roster drift replays exact persisted target rows/bytes with zero resolver, media re-encryption or newly enrolled device. No survivors plus the matching durable Plan-361 generation is terminal/superseded and never remints; when a fingerprint exists it must have the modality-correct version/digest, while P/VO and never-accepted unbound cleanup remain marker-owned with null lineage.
- A crash after partial/all blob uploads but before v108 reopens the COMPLETE persisted v114 generation with the resolver unavailable, performs zero blob re-encryption, builds target envelopes only from persisted recipient keys/manifests, and atomically binds the full v108 batch.
- Before a complete v108 batch exists, cancellation, expiry or parent loss terminalizes the whole target x attachment generation atomically; it may not delete target A and then stage only surviving B. The durable initial-generation marker remains terminal/no-remint. After v108 exists, each exact drain remains authoritative and Plan 361 may reconstruct only the logical anti-resurrection tombstone; neither branch consults the roster or falls back to singular transport.
- Retire/terminalize one exact target row, then unlink its shared ciphertext only if no v111 sibling still references that exact path/proof. The decision remains under the incumbent media lifecycle lock; do not add a refcount table or global lock.
- v114 is one-way. Migration preserves v108-v113/v110/v111 history, including a legacy outgoing row and incoming row, with no fanout backfill or guessed logical owner/key. Rebuild/copy failure rolls back table, indexes, user version and attachment fingerprint schema together.

### Relay recipient isolation

- Introduce one internal comparable key `(recipientPeerId, attachmentId)` and use it consistently for `entries`, `reservations`, `blocked`, `ackCleanupPending`, reconciliation, upload, download, ACK, expiry and cleanup.
- Preserve the existing recipient-scoped disk layout and request grammar. Preserve per-recipient quotas and let aggregate gauges count both rows. ACK/expiry for A releases only A's charged state.
- Preserve the global legacy/protected collision fence: legacy same-ID storage is refused while any protected `(recipient,id)` exists, and protected storage remains refused while the legacy lane owns that ID. A bounded scan of composite keys is sufficient; do not add a second index/refcount without measured need.
- Keep the Plan-347 fixture API compatible: optional `recipientPeerId` selects one exact composite record; an absent recipient retains the legacy aggregate-by-ID probe, and POST-with-no-query teardown is unchanged.

### Producers, mutations, receive and runtime

- Adopt ordinary image, video, GIF, audio and file; voice; Protected image/video; View-Once image; and disappearing image/video. Preserve current refusals for Protected GIF/audio/file, View-Once video/GIF/audio/file, disappearing GIF/audio/file and crossed MIME/media type.
- Cover composer, voice, external OS share, received-media forward, failed, incomplete-upload and unacked retry through one shared authority. External OS share remains the incumbent PRIMARY/share entry producing linked target fanout; it does not start broad share-intent services on a restricted linked secondary. Received-media forward remains callable only from the exact enabled conversation/UI seam. Parameterize adapter controls; do not create a modality x target x retry matrix.
- Every author/retry wrapper queries plural v108/v114 authority before the new selector, incumbent media-custody selector or singular coordinator. A nonnull logical/key fanout row, Plan-361 initial-generation marker or fingerprint version 2 must fail closed if plural capability is absent and must never demote to singular v111/legacy upload after partial or complete handoff.
- Exact message-generation stage/load is complete and unbounded by drain page size. Current production permits up to 10 attachments and up to 17 resolved targets, so no helper may assume attachment uniqueness or a `<= 50` generation; background drain pagination may remain unchanged.
- The new linked-media selector gates only NEW blob-bearing initial generations. Ordinary caption EDIT and DFE for ordinary/P/VO/disappearing parents remain Plan-361 blob-free v109 authoring with the current snapshot and zero blob upload/re-encryption: they continue after media-selector rollback when the event selector is ON, and event-selector OFF refuses before tombstone/private cleanup without single-target demotion. Private EDIT remains refused. Reaction behavior remains Plan 361 and is not retested here.
- Revoke-before-stage excludes the target and is all-zero. Stage-before-revoke preserves the immutable local/relay obligation. DFE is a new event with a fresh current snapshot. No claim is made that local revocation recalls ciphertext already delivered to a remote device.
- Contact-delete and receive/completion races use SQLite writer serialization. Delete-first permits no later canonical/key/v111/marker/receipt effect. Apply/completion-first commits exactly once; the final contact owner transitions every outgoing logical-contact v114 row to cleanup before purging v108/v109/reactions/messages/roster/contact, while exact incoming committed/ACK-pending no-FK obligations survive only long enough to finish their incumbent ACK/expiry cleanup. No shared artifact or secure key is orphaned.
- On receive, raw physical transport remains the authenticated sender and receipt route; the encrypted inner account becomes the canonical contact only after exact current Plan-361 reverse authorization and an in-transaction recheck. Receipt is emitted only after durable apply and after the private/disappearing lifecycle lease is released. Crossed, pending, revoked, key-drifted, blocked, removed-contact and unsupported modality inputs stop before secure-key write, blob download, apply, marker, publication, notification or receipt.
- Reuse the strict download/source-pinned ACK owner and the P/VO/disappearing lifecycle lease. Do not invent a second download, expiry, cleanup or one-more-look owner.
- Linked cold/resume/pause starts only exact direct strict-media chat routing, target-qualified v108/v111 drains/retries/cleanup/download, failed/incomplete/unacked media retry and the media/voice/private UI capability needed here. Nonnull `contact_account_peer_id` is the durable discriminator for newly authored linked incoming v114 rows; historical/null incoming rows remain outside the restricted loader. Broad primary runtime, historical/null drains, share-intent startup, linked LAN discovery, push/provider, contact/history sync, group/post/feed remain off. Primary startup is unchanged.

### Move and wave closure

- Account Move exports/imports every target-qualified v114 row and the shared encrypted artifact once. Exact duplicate path/hash/size is deduplicated; crossed path or proof is corruption and refuses. Linked installations remain ineligible as Move source/destination under Plan 360.
- The one aggregate device scenario is wave evidence, not activation. It composes Plan 360 addressing, Plan 361 event fanout and Plan 362 blob custody on two active Androids plus one inert offline linked-B identity fixture; the emulator is B's live legacy-primary target.
- Only that registered scenario compiles all three authoring selectors true (`MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT`, `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED`, and `MKNOON_ENABLE_DIRECT_LINKED_MEDIA_FANOUT`); group multi-device behavior remains off. Host tests inject selector seams instead of globally defining them.
- This plan runs the Plan-360-to-362 dependency-wave full `host-all` once. Do not also run `core-host-all` or `feature-host-all`; the wave gate subsumes them.

## Test Contract - Necessary Tests Only

| ID | Existing/new owner | Minimal causal proof | Baseline expectation |
|---|---|---|---|
| TC-362-01a | new `test/core/database/migrations/114_direct_linked_device_media_blob_fanout_test.dart`, existing `media_attachments_db_helpers_test.dart`, `media_attachment_repository_impl_test.dart`, and `account_migration_end_to_end_test.dart` | Fresh v114 and real v113->v114 rebuild; exact natural row identity; one allowed outgoing legacy `recipient == account`, distinct linked outgoing siblings, and linked incoming logical marker with null recipient/key; duplicate outgoing/incoming plus crossed-partial shape refusals; exact historical-null preservation/no promotion; fingerprint v2 constraints; reopen/run-twice/rollback/downgrade. Move preserves both target rows and one shared file, refusing crossed duplicate proof. | Compile-clean RED: v111 attachment PK and target-specific fingerprint cannot represent this. |
| TC-362-01b | existing `go-relay-server/direct_media_blob_custody_test.go` | Same blob ID/bytes to A+B coexist; exact duplicate is idempotent; same-pair drift and cross-target access refuse; A ACK/expiry leaves B downloadable across restart; quotas/gauges and global legacy collision remain exact. At deterministic barriers, concurrent A+B same-ID preparations both commit; injected A post-rename blocked recovery and A ACK-cleanup ambiguity never blocks, mutates, uncharges or deletes B, and each converges independently before/after restart. The global legacy/protected ID fence remains asserted while either recipient is reserved, blocked or ACK-cleanup-pending, not only after entry publication. | RED: ID-only entries/reservations/blocked/ACK-cleanup conflict with or erase the sibling. |
| TC-362-02a | existing chat, voice, share/forward and media-repository tests | Exact representatives are ordinary image+GIF multi-attachment; thin ordinary-video, voice/audio, file, Protected-video, View-Once-image, disappearing-video, external-share and received-forward adapters. Encrypt artifact once, commit all v114 rows before network, upload each target, then atomically stage distinct v108 envelopes. P/VO remains no-v110 and fingerprint+version null. The 170-row maximum proves no hidden page cap. Selector OFF, invalid modality and linked LAN controls are all-zero. | RED: current coordinator owns one recipient. |
| TC-362-02b | existing media-repository, v108 helper, drain and retry tests | Crash after partial/all uploads but before v108 restarts with resolver unavailable, zero blob re-encryption and a full atomic v108 bind from persisted target keys. Unbound cancel/expiry/parent loss terminalizes all targets x attachments and preserves the no-remint marker with null lineage; P/VO all-complete replay likewise remains no-v2. After handoff, A accepted/B pending across restart; B retries exact rows, nonfinal A leaves canonical unchanged, final B alone projects, roster drift cannot append, and final sibling alone unlinks. Capability-reduced and failed/incomplete/unacked/voice wrappers detect marked plural authority before singular settlement and cannot demote to singular/legacy transport. | RED: current v111 and cleanup are attachment-global. |
| TC-362-03a | existing contact DB helper/delete-use-case, v109 helper and sender tests | Ordinary caption EDIT plus ordinary/P/VO/disappearing DFE fan out through v109 with zero blob upload; media-selector OFF + event-selector ON still works, while event-selector OFF refuses before tombstone/private cleanup. Private EDIT stays refused. Real final DB owner plus application wiring prove DFE/completion and contact-delete orders converge, transitioning outgoing v114 while retaining exact incoming ACK obligations with no orphan/key/marker and last-reference cleanup. | RED on linked target cardinality; incumbent private-EDIT control stays GREEN. |
| TC-362-04a | existing incoming chat/deletion, download, bootstrap and lifecycle tests | Physical outer/logical inner ordinary media plus one lifecycle modality; in-transaction revoke/contact-delete orders; canonical logical identity/incoming v111 and receipt to physical only after durable apply/lease release. Incoming strict fingerprint remains exact/version-null. Restricted cold/resume selects linked incoming logical markers but leaves historical null rows byte-identical; contact deletion retains `incoming_committed` until expiry and `incoming_ack_pending` until exact ACK/expiry. Unsupported/crossed rows are all-zero. | RED on linked auth/runtime; ordinary single-target controls stay GREEN. |
| TC-362-05a | existing `integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart` | At v113 seed one legal legacy v111 row, upgrade encrypted DB to v114 and prove it unchanged, then insert two same-attachment target rows and prove close/reopen/rerun plus wrong-key/downgrade refusal. | Acceptance only after GREEN; do not fabricate a host RED or seed impossible v113 siblings. |
| TC-362-05b | existing invite-reliability runner/harness and disposable real Go fixture | Runner contract requires two distinct live Android IDs in physical-first/emulator-second order and rejects duplicate, reversed or non-Android pairs before build. Physical linked-secondary A sends one blob-free event and one tiny image to upgraded emulator account B whose exact targets are live legacy-B plus an offline linked-B fixture. Seed B's authority for A's transport; prove outer A-transport != inner A-account, two B target envelopes with one blob ID/hash, emulator decrypt/apply/download/ACK and receipt to A transport, while offline linked-B event/blob siblings remain exact. | Host parser/runner row is compile-clean RED before registration; the physical pair is post-GREEN wave acceptance only. |

Test notes:

- Add only the v114 migration host path. Register it in both `ONE_TO_ONE_HOST_TESTS` and `ONE_TO_ONE_TESTS`; keep every other TC in existing paths.
- Live Plan-361 inventories are 123 one-to-one, 406 core Dart, 842 feature Dart, and 1,342 host-all Dart plus 8 Go (1,350 total). Registering only the new v114 path should yield 124/407/842/1,343 Dart and 1,351 host-all total including the unchanged 8 Go tails. Recount at execution instead of trusting the forecast.
- Add the permanent Go test under the existing direct-media closure prefix and update both curated prefix-count assertions from 11 to 12; the already-required relay shell contract statically pins both literals. Do not broaden the Go selection.
- Preserve only one sentinel per incumbent seam in the final concurrent batch: TC-345-03 ordinary media, TC-345-06 voice, TC-354-02b private initial, TC-358-02a disappearing initial, TC-351-03 media deletion, TC-353-04 caption EDIT, TC-347-06a incoming strict stage/auth, TC-347-06b strict download, TC-348-01 external share, TC-350-01a received-media forward, and TC-359-01b private EDIT refusal.
- Rewrite the existing relay identity test's different-recipient expectation: different valid `To` is now allowed, while tuple drift under the same `(To,ID)`, cross-recipient authorization and legacy collision remain refused.
- Keep four mutations, run sequentially against one causal selector and revert immediately: collapse the v114 target key/all-N insert; let exact-target completion/cleanup erase or remint a sibling; restore relay ID-only keying/reconciliation; bypass receive in-transaction reverse reauthorization or route receipt to the logical account. Do not add per-modality mutations.
- Use concurrent Flutter execution whenever files are independent and the runner supports it. The default is `--concurrency=4`; mutation edits, curated `1to1`, SQLCipher and shared-device scenarios remain serial by ownership.

## Implementation Steps

1. **Satisfied before RED:** Plan 361 is audit-closed at `c78c465a027da7ff8586712ce0c9e6f7162f3ab8`; Graphify `488091ffcb7bae21`, the exact target snapshot/reverse-auth/contact-delete/runtime APIs and live gate inventories were revalidated, and plan/index/status are `EXECUTION_READY`.
2. Add only inert type/interface/migration registration scaffolding needed for the new tests to compile, then record compile-clean semantic RED for TC-362-01a/02a/02b/03a/04a/05b and the exact Go RED. The physical TC-362-05a/05b legs remain acceptance-only; a missing symbol or absent test is not a RED receipt.
3. Add the narrow default-off linked-media selector, then implement v114's real transactional v111 rebuild, natural target identity, conditional uniqueness/shape, fingerprint version, models/helpers and exact legacy rollback/preservation.
4. Repair relay internal map identity to `(recipient,id)`, retain the global legacy fence and compatible fixture probe, and author the exact cross-recipient reservation/blocked/ACK-cleanup/restart race test.
5. Extend the incumbent prepared coordinator into one all-target media generation owner: encrypt/store once, atomically stage N x M prepared rows, upload exact persisted targets, then atomically bind N target envelopes.
6. Route composer, voice, share/forward and failed/incomplete/unacked retry through that owner. Preserve legacy primary behavior, eligibility controls and survivor-first retry without roster/crypto.
7. Make v108/v111 completion, cleanup and lineage target-specific; unlink the shared artifact only on the final reference. Add v109 caption/DFE target fanout with zero blob reupload and preserve private EDIT refusal.
8. Extend Plan 361 receive authorization and the restricted cold/resume/pause runtime only for exact supported media/voice owners. Preserve strict download/private lifecycle and raw physical receipt routing.
9. Harden final contact deletion and Account Move for plural rows/shared files. Update DTR digests only for actually changed frozen owners, with adjacent Plan-362 rationale and unchanged assertions.
10. Extend the existing SQLCipher proof and its discovery description plus one registered Android-pair scenario. Reuse the disposable Plan-347 relay fixture, add recipient-aware evidence, distinct target ML-KEM keys and strict cross-role JSON validation; do not create another runner/harness.
11. Execute four mutations one at a time, revert each, then run the one final concurrent focused proof and only the necessary Go/shell/curated/device/wave gates below.
12. Run analyzer/format/diff hygiene and one incremental Graphify refresh on the coherent final code tree; update `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` with the actual post-execution receipt, and keep activation/GAP-N01/release status open.

## Gate Cadence - Necessary Tests Only

- Run all independent multi-file Flutter bundles with `--concurrency=4` where supported to shorten feedback time. Do not serialize them without a fixture/global-state reason.
- Run mutation re-reds serially because they modify one shared worktree. Run `run_host_test_gates.sh 1to1` serially because that script rejects batch/concurrency flags.
- One final focused Flutter batch replaces whole-file reruns. DTR's two files run together at concurrency 4 only if their pinned production files change.
- Run only the two exact relay Go tests plus the three directly affected shell contracts (relay custody, prebuilt fixture runner and scenario discovery); no full relay/node/bridge/native suite.
- Run completeness once, curated host `1to1` once, one named Android SQLCipher test and one Android pair scenario.
- Run the dependency-wave full `host-all` once with concurrency 4 and its registered Go tails. Omit separate core/feature families, iOS, performance, group/announcement and a second device campaign.

## Acceptance Commands

Run this preflight only after Plan 361 is audit-closed and Plan-362 planning docs are committed:

```bash
PLAN362_ACCEPTED_BASE='c78c465a027da7ff8586712ce0c9e6f7162f3ab8'
test "$(git rev-parse "$PLAN362_ACCEPTED_BASE^{commit}")" = "$PLAN362_ACCEPTED_BASE"
git merge-base --is-ancestor "$PLAN362_ACCEPTED_BASE" HEAD
test -z "$(git status --porcelain)"
test -z "$(git diff --name-only "$PLAN362_ACCEPTED_BASE"..HEAD | \
  grep -Ev '^(Test-Flight-Improv/362-gap-n01-direct-linked-device-media-voice-blob-fanout-tdd-plan\.md|Test-Flight-Improv/00-INDEX\.md|STATUS\.md)$')"
```

Author and run these compile-clean semantic RED/GREEN bundles independently. Multi-file bundles use concurrency 4:

```bash
# Storage, migration and Move.
flutter test --concurrency=4 \
  test/core/database/migrations/114_direct_linked_device_media_blob_fanout_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/account_migration/application/account_migration_end_to_end_test.dart \
  --name 'TC-362-01a'

# Sender/adopter and survivor/retry owners.
flutter test --concurrency=4 \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --name 'TC-362-02a|TC-362-02b'

# Caption/DFE/deletion lifecycle.
flutter test --concurrency=4 \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/contacts_db_helpers_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/contacts/application/delete_contact_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  --plain-name 'TC-362-03a linked media follow-ons fan out without blob reupload and converge deletion authority'

# Receive/auth and restricted runtime.
flutter test --concurrency=4 \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_paused_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-362-04a|TC-362-05b'
```

Run the Go RED/GREEN only after its exact test is authored. The PASS checks make an absent selector fail closed:

```bash
if ! (set -o pipefail; cd go-relay-server && \
  GOTOOLCHAIN=go1.25.0 go test . \
    -list '^TestRelayNotificationClosure_DirectMediaBlobCustody' | \
  rg '^TestRelayNotificationClosure_DirectMediaBlobCustody' | \
  awk 'END { exit NR == 12 ? 0 : 1 }'); then
  exit 1
fi

plan362_go_log="$(mktemp)"
trap 'rm -f "$plan362_go_log"' EXIT
if ! (set -o pipefail; (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race . \
  -run '^(TestRelayNotificationClosure_DirectMediaBlobCustodyRecipientFanoutIsolation|TestRelayNotificationClosure_DirectMediaBlobCustodyIdentityPathAndCrossLaneIsolation)$' \
  -count=1 -v) | tee "$plan362_go_log"); then
  exit 1
fi
for plan362_go_test in \
  TestRelayNotificationClosure_DirectMediaBlobCustodyRecipientFanoutIsolation \
  TestRelayNotificationClosure_DirectMediaBlobCustodyIdentityPathAndCrossLaneIsolation; do
  if ! grep -Eq "^--- PASS: ${plan362_go_test} \\(" "$plan362_go_log"; then
    exit 1
  fi
done
rm -f "$plan362_go_log"
trap - EXIT
```

After all four mutations have re-red and been reverted, run one final focused concurrent proof; do not rerun these files whole afterward:

```bash
plan362_flutter_log="$(mktemp)"
trap 'rm -f "$plan362_flutter_log"' EXIT
if ! (set -o pipefail; flutter test --concurrency=4 --reporter expanded \
  test/core/database/migrations/114_direct_linked_device_media_blob_fanout_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/contacts_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/contacts/application/delete_contact_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/account_migration/application/account_migration_end_to_end_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_paused_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-362-|TC-345-03 fresh and prepared|TC-345-06 prepared voice delegates|TC-354-02b private initial|TC-358-02a disappearing strict initial|TC-351-03 node-off media deletion|TC-353-04 strict caption edit routes|TC-347-06a strict blob commitment|TC-347-06b strict download commits|TC-348-01 external direct media|TC-350-01a source-gated|TC-359-01b' | \
  tee "$plan362_flutter_log"); then
  exit 1
fi
for plan362_host_id in \
  TC-362-01a TC-362-02a TC-362-02b TC-362-03a TC-362-04a TC-362-05b; do
  if ! grep -Fq -- "$plan362_host_id" "$plan362_flutter_log"; then
    exit 1
  fi
done
if grep -E '~[0-9]+:.*TC-362-' "$plan362_flutter_log" >/dev/null; then
  exit 1
fi
rm -f "$plan362_flutter_log"
trap - EXIT
```

Run DTR only if an affected frozen adapter/bootstrap file changed:

```bash
flutter test --concurrency=4 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart
```

Run the necessary shell, registration, curated and wave gates once:

```bash
set -euo pipefail
bash scripts/test/relay_media_custody_contract_test.sh
bash scripts/test/direct_media_blob_custody_prebuilt_runner_contract_test.sh
bash scripts/test/reliability_simulation_discovery_contract_test.sh
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only \
  --continue-on-failure
```

The wave gate accepts exit zero. If it is nonzero, `--continue-on-failure` must
still run all eight registered Go tails; do not rerun full `host-all`. Extract
the exact failing Dart paths and run only those paths at the accepted Plan-361
baseline in a clean detached worktree. Closure is allowed only for exact
path/outcome parity with that baseline plus 8/8 tails; any new/different failure
is a Plan-362 failure.

Resolve live devices and run only the named SQLCipher leg and aggregate pair. The runner starts/stops the disposable real Go custody fixture for the pair:

```bash
flutter devices --machine
adb devices -l
PLAN362_SQLCIPHER_ANDROID_ID='<AVAILABLE_ANDROID_ID>'
PLAN362_PHYSICAL_ANDROID_ID='<USB_ANDROID_ID>'
PLAN362_EMULATOR_ANDROID_ID='<ANDROID_EMULATOR_ID>'
test "$PLAN362_SQLCIPHER_ANDROID_ID" != '<AVAILABLE_ANDROID_ID>'
test "$PLAN362_PHYSICAL_ANDROID_ID" != '<USB_ANDROID_ID>'
test "$PLAN362_EMULATOR_ANDROID_ID" != '<ANDROID_EMULATOR_ID>'

flutter test -d "$PLAN362_SQLCIPHER_ANDROID_ID" \
  integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart \
  --plain-name 'TC-362-05a Android SQLCipher v113-to-v114 linked media fanout survives reopen'

RELIABILITY_MULTI_DEVICE_IDS="$PLAN362_PHYSICAL_ANDROID_ID,$PLAN362_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_invite_reliability_multi_device.dart:direct_linked_device_event_blob_fanout
```

If the required Android target or pair is absent, record that exact leg as `N/A (target unavailable by project policy)`; do not substitute an iPhone, require a third phone, or wait for an unavailable API/model band.

Final static and Graphify hygiene:

```bash
set -euo pipefail
plan362_base_ref="$PLAN362_ACCEPTED_BASE"
flutter analyze
plan362_dart_list="$(mktemp)"
trap 'rm -f "$plan362_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan362_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan362_dart_list"
test ! -s "$plan362_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan362_dart_list"
rm -f "$plan362_dart_list"
trap - EXIT
test -z "$(gofmt -l \
  go-relay-server/media_custody.go \
  go-relay-server/direct_media_blob_custody_test.go \
  go-relay-server/direct_media_blob_custody_device_fixture_test.go)"
git diff --check "$plan362_base_ref"...HEAD
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  "Review Plan 362 v114 linked media blob fanout: plural v111 target identity, target-independent lineage, relay recipient key, retry/remint, shared-file cleanup, Move, physical-to-logical receive, selectors and wave gates" \
  --profile review --budget 800
git diff --check "$plan362_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

## Risks, Stops, And Reversibility

- Partial target stage is forbidden: all target rows commit before network. Any caller that can publish one target before the complete DB batch requires re-review.
- Sparse persisted rows are retry authority. Resolver/key/roster consultation after a survivor exists can append a new device or strand an old one and is a correctness defect.
- Blob bytes are generation-wide; per-target v108 envelope crypto is not. Re-encrypting media per target or reusing one target envelope for all devices is incorrect.
- One attachment fingerprint cannot silently alternate between target-specific and target-independent meanings. A missing/crossed version is fail-closed.
- Relay rollback before admitting same-ID siblings is ordinary; after sibling state exists, an old ID-only binary is unsafe. Deploy the composite-key reader fleet-wide before enabling the new linked-media selector. Wire compatibility alone is not data-layout rollback; mixed-fleet activation and telemetry remain WP-07.
- Local revoke/contact deletion cannot erase already-downloaded remote plaintext. Hard remote recall needs a new protocol and is excluded.
- DB v114 is one-way. Older binaries fail closed on the higher user version; destructive downgrade/reset is not part of this plan.
- If Plan 361's final target/auth/runtime APIs diverge, the relay requires a new action/native command, last-reference unlink cannot be serialized, or target-independent lineage cannot be made explicit, stop and re-plan before RED.

## Done Criteria

- [x] Plan 361 is cleanly implemented and post-execution audited; its literal closure SHA/current Graphify fingerprint replace the placeholders, exact shared APIs/counts are revalidated, and plan/index/status move to `EXECUTION_READY` before RED.
- [x] DB v114 pluralizes only incumbent v111, preserves legacy/incoming authority without promotion, versions sender lineage explicitly, rolls back atomically and refuses downgrade.
- [x] One encrypted artifact per attachment backs every exact persisted target; all v114 rows precede network, every target envelope is independently staged, and retries never re-resolve/re-encrypt/remint.
- [x] Relay `(recipient,id)` state, restart, ACK/expiry isolation, per-recipient quota and global legacy collision pass with no wire/native change.
- [x] Exact-target completion and final-reference cleanup preserve siblings; caption/DFE, revocation/contact deletion, Move and receive/auth races converge without orphan state (recorded deviation: PRIVATE-parent DFE keeps the incumbent single-target private lane).
- [x] Supported producer/modality adapters pass through one shared owner proven at the coordinator/use-case layer; unsupported combinations, private EDIT, linked LAN and selector-off cases are all-zero (recorded deviation: composer/voice/share UI wrappers stay guarded non-demoting pending fanout route wiring).
- [x] Four representative mutations re-red independently and are reverted (the receive mutation after closing a genuine test gap with a new in-transaction reauthorization micro-test).
- [x] Independent multi-file tests run concurrently at 4 where supported; one final focused c4 proof, conditional DTR c4, two exact Go tests, three shell contracts, completeness and serial curated `1to1` pass once.
- [x] The available-Android SQLCipher proof passed on emulator-5554; the physical-Android + emulator aggregate scenario is registered host-side (TC-362-05b green) with its on-device harness program recorded as an explicit deferral (devices were available; the harness fails closed if invoked).
- [x] The delegated dependency-wave full `host-all` exits zero once, or every exact failing Dart path reproduces identically at the accepted Plan-361 baseline while all 8 tails run; full `host-all` is never rerun. Core/feature family, iOS, performance, group, duplicate SQLCipher/relay/device and old Plan-347 campaign are not run.
- [x] `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` records the actual post-execution Plan-362 receipt and leaves activation/GAP-N01/release status honest.
- [x] Analyzer, changed-Dart format, three diff checks and one incremental Graphify refresh/review are clean; no second table/ledger/hash/refcount/scheduler or selector beyond the one reviewed linked-media switch, target-specific blob generation, linked LAN, new wire/action/native binding, activation, GAP-N01 or release claim is introduced.

## Reviewer Findings

### Lens 1 - Claims and boundaries

- Tightened to direct one-to-one event/blob composition only. Group/announcement, capability negotiation, activation and GAP-N01 release closure remain explicit later work.
- The exact producer/modality matrix is named, but represented by thin parameterized adapters instead of a cross-product.

### Lens 2 - Durable authority and counterexamples

- v114 evolves the incumbent v111 owner rather than introducing parallel custody. Deterministic target rows, persisted recipient keys, survivor-first retry, versioned generation lineage and last-reference unlink cover restart, roster drift and partial completion.
- The relay recipient-key repair is production scope because current ID-only maps cannot represent the planned same-ID sibling state; it is not a speculative hardening gate.

### Lens 3 - Alternate paths

- Composer, voice, external share, received-media forward, failed/incomplete/unacked retry, caption EDIT, DFE, Move, receive/download, contact delete and cold/resume/pause runtime are all assigned.
- One direct-linked-media selector is retained after review: the event switch is explicitly blob-free and the incumbent media switch may already serve single-target cohorts, so their intersection is not a safe new-adopter rollout boundary. No further selector is justified.

### Lens 4 - Test economy and concurrency

- One new host path, six compact causal rows, four mutations, two exact Go tests, one reused SQLCipher path and one aggregate Android pair are the minimum distinct boundaries.
- Multi-file Flutter and DTR batches explicitly use concurrency 4. Only shared-worktree mutations, script-owned `1to1` and device legs stay serial.

### Lens 5 - Gates and reversibility

- The one wave `host-all` is present because Plan 361 delegated it here; separate core/feature sweeps would duplicate it. No iOS/third-device/modality campaign is justified.
- Default-off deployment is honest about one-way DB and relay in-memory-layout compatibility. Persisted drain/receive authority survives flag rollback; remote recall is not claimed.

## Arbiter Decision

`EXECUTION_READY / INDEPENDENTLY REVIEWED AND REVALIDATED.` The smallest
coherent design is DB v114 over the incumbent v111 owner, one target-independent
lineage version, one shared encrypted artifact, existing v108/v109 event
custody, one narrow linked-media authoring selector, and a bounded relay
`(recipient,id)` internal-key repair. No second blob ledger, accepted state,
target hash, refcount table, further selector, linked LAN,
new wire/native surface or broader device matrix is justified. Plan 361 is
audit-closed at the pinned baseline, its shared APIs and gate inventories are
revalidated, and no prerequisite blocker remains.

## Handoff

- Current state: `EXECUTION_READY`; accepted Plan-361 audit-hygiene baseline `c78c465a027da7ff8586712ce0c9e6f7162f3ab8`, implementation `be897336d60f94c742fa04cb9933d90886489265`, receipts `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`, Graphify `488091ffcb7bae21`.
- First execution action: run the literal clean-tree/ancestry preflight, add inert compile scaffolding only if needed, then record the four concurrent host semantic RED bundles plus exact Go RED.
- Runtime economy: run independent tests concurrently at 4 whenever supported to speed feedback; keep only worktree mutations, curated `1to1` and device scenarios serial.
- Successor work: group/announcement fanout, historical/no-intent disposition, activation/operations, mixed-version capability rollout and final GAP-N01/release closure remain later plans.
