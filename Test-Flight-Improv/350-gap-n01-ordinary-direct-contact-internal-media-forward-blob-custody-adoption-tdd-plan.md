# 350 - GAP-N01 Ordinary Direct-Contact Internal Media-Forward Blob Custody Adoption

Status: **EXECUTION-READY / INDEPENDENT REVIEW PASSED / NOT IMPLEMENTED** (2026-08-09)
Type: Modification
Baseline: `f11a732568aa0c72c8d4ed8bfecd5b1348adf130` (`feat: add direct text mutation custody`), including `Plan 349 — EXECUTION_COMPLETED`
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5 requirements 1, 3, and 6 plus A-01/A-02/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01
Classification: implementation-ready; bounded internal-forward adopter; core reuse bet confirmed
Closure tier: host-only causal application and real-file SQLite recovery proof, exact preservation sentinels, host `1to1`, `core-host-all`, and serial `feature-host-all`. No DB migration, full `host-all`, Go/native/bridge/relay run, Android device run, or iOS run.

## Planning Progress

| Time | Role | Files inspected | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-08-09 | Evidence collector | `STATUS.md`; GAP-N01/WP-01; Plans 347-349; share coordinator, received/direct-library/group-forward source gates, fresh v111 coordinator/repository/DB helpers, retry, tests, and gate inventories | Plan 348 intentionally left every internal media forward on legacy upload. Three already-authorized internal source families converge on the same direct-contact sender after their existing source and target checks. | Reuse the Plan 348 fresh owner and Plan 347 retry/network owner; enumerate every authorized entry. |
| 2026-08-09 | TDD planner | Graphify architecture query plus current source/test verification | The smallest sufficient change is one entry-derived internal-forward adopter and one exact forwarded-parent alternative in existing fresh validation. No new durable owner, schema, protocol, selector, or scheduler is justified. | Create four causal/preservation bundles, then run an independent `$tdd-review`. |
| 2026-08-09 | Independent TDD review | Fresh factual, DB/retry, and boundary/reversibility audits over the first complete draft | Core reuse bet confirmed; direct-library authority was cited at the wrong layer, exact forward authorization was not independently threaded, the private authority re-read and LAN order were not causal, and post-commit observer/cleanup exceptions needed an explicit boundary decision. | Apply bounded plan fixes and run a fresh re-review; add no persistent kind, owner, schema, protocol, or device work. |
| 2026-08-09 | Review arbiter | Revised plan, source trust/TOCTOU and snapshot-owner boundaries, literal test fixtures/gates, three fresh `$tdd-review` verdicts, and baseline relay-media owner shell | Verdict `ready`; core bet `confirmed`; disposition `execute`. Direct-library ordering stays in its recording application harness, SQLite/restart proofs remain separate, and exceptional snapshot cleanup stays with Plan 249. The baseline owner shell passed. | Append `EXECUTION_READY`; do not implement in this planning/review session. |

## Problem And Evidence

- Behavior to improve: an authorized in-app ordinary-media Forward to a direct contact should gain the same durable parent/attachment/v110/v111 authority as Plan 348's external share before LAN or relay work, and should recover from the exact v111 ciphertext after restart.
- Impact: the current internal-forward contact leg can finish its source and target authorization, then begin legacy upload with no recoverable local blob owner. A process stop in that window can lose the forward even though the corresponding external-share and composer/voice producers already have strict custody.
- Confirmed current gap: `DefaultShareBatchDeliveryCoordinator._sendToContact` selects strict custody only when `externalOrdinaryShare` is true and both forward-authority fields are absent (`lib/features/share/application/share_batch_delivery_coordinator.dart:1654-1671`); every authorized internal contact forward therefore falls through to LAN/legacy `runUploadMedia` before a parent or v111 row exists (`:1682-1763`).
- Confirmed entry families:
  - `deliver()` recognizes internal provenance, reloads current destinations, and for received direct media holds an immutable `BuildReceivedMediaForward.captureForDispatch` lease through delivery (`lib/features/share/application/share_batch_delivery_coordinator.dart:415-500`, `:563-610`; `lib/features/conversation/application/build_received_media_forward.dart:227-329`).
  - `DirectMediaBatchForwardDeliveryCoordinator` revalidates each direct-library source item before it calls the trusted `deliverDirectMediaBatchForwardStrict()` application port; that port then enforces one processed item and reloads each current contact (`lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart:282-303`, `:417-529`; `lib/features/share/application/share_batch_delivery_coordinator.dart:740-860`). Production composes the chain at `lib/features/conversation/presentation/screens/conversation_wired.dart:6353-6365`.
  - `deliverGroupMediaForward()` verifies and snapshots the exact discussion/announcement source, then `_deliverForwardTarget` reloads each contact before `_sendToContact` (`lib/features/share/application/share_batch_delivery_coordinator.dart:864-1004`, `:1027-1062`). Group destinations are not in scope.
- Confirmed reuse: Plan 348 already provides the absent-parent atomic parent + complete attachments + v110 + v111 transaction, secure-key ambiguity compensation, authority-aware result mapping, preview copy, foreground lease, and source-free retry through `PreparedDirectMediaBlobCustodyCoordinator.prepareAndUploadFreshMessage` and `retryIncompleteUploads`.
- Required narrow generalization: the sender coordinator, repository, DB helper, and exact-authority re-read deliberately accept only the marker-free external shape `dedupKey == id && !isForwarded` (`lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart:164-195`; `lib/features/conversation/data/repositories/media_attachment_repository_impl.dart:807-865`; `lib/core/database/helpers/media_attachments_db_helpers.dart:2347-2361`; `lib/features/share/application/share_batch_delivery_coordinator.dart:1505-1599`). Internal forwards require one independently supplied ephemeral `authorizedForwardDedupKey`; every layer must require `isForwarded` and exact parent-token equality while retaining every other fresh ordinary-parent invariant. The token is not persisted and is not a new authority owner.
- Existing coverage: Plan 348's TC-348-01/02/03/04 prove external authority ordering, exact fresh ownership, post-authority truth, and restart; existing forward tests prove source qualification, target reload, per-target identity, provenance, preprocessing, matrix retry, and snapshot disposal. They intentionally do not prove strict custody for an internal forward.
- Missing coverage: no production-path test observes v111 authority before the first network call for all three internal source families; TC-348-05 currently asserts that an internal forward remains legacy.
- Refuted finding: a new DB version, outbox, retry queue, artifact store, transport helper, relay/native kind, rollout flag, or mobile harness is not required. The event, blob, lifecycle, and restart authorities already exist and have the required lifetime.
- Unresolved findings: none inside this bounded slice. Plan 249's post-revalidation TOCTOU and exceptional snapshot-owner failures are explicit accepted/deferred boundaries, not Plan 350 blockers.
- Affected production/test/gate files: `lib/features/share/application/share_batch_delivery_coordinator.dart`; `lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart`; `lib/features/conversation/domain/repositories/media_attachment_repository.dart`; `lib/features/conversation/data/repositories/media_attachment_repository_impl.dart`; `lib/core/database/helpers/media_attachments_db_helpers.dart`; `lib/app/bootstrap/production_application_bootstrap.dart`; their existing tests and shared real-DB fixture; `test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart`; `test/features/share/integration/external_share_media_custody_recovery_test.dart`; and the wording-only bounded-adopter receipt in `scripts/test/relay_media_custody_contract_test.sh`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `2e40a3ca21a44aea`; current at planning time.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 350 ShareBatchDeliveryCoordinator ordinary in-app internal media forward direct contact strict v110 v111 v108 custody adoption forwardProvenance directForwardSourceAuthority deliverDirectMediaBatchForwardStrict deliverGroupMediaForward" --profile tdd --budget 700`.
- Anchors: `deliverDirectMediaBatchForwardStrict` -> `lib/features/share/application/share_batch_delivery_coordinator.dart:747`; `DirectForwardSourceAuthority` -> `lib/core/services/share_intent_model.dart:20`; `forwardProvenance` -> `lib/features/conversation/application/build_direct_media_library_batch_forward.dart:44`.
- Surfaced proof/gate files: `test/features/share/application/share_batch_delivery_coordinator_test.dart`; `test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart`; `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart`; host/non-host `1to1` and AUTO feature ownership.
- Graph gaps requiring source search: exact fresh-parent guards, group/announcement contact branch, recovery fixture, source contract, and gate registration were verified directly because the compact graph returned only a shortlist.
- Reuse rule: these anchors may be handed to review/execution, but current source and literal commands remain authoritative.

## Scope Contract And Guard

In scope:

- Adopt strict blob custody, under the existing default-off selector, for exactly these already-authorized ordinary-media destinations: received direct media forwarded through `deliver()` to a contact; one direct-library item sent through `deliverDirectMediaBatchForwardStrict()` to contacts; and verified discussion/announcement media sent through `deliverGroupMediaForward()` to contact destinations.
- Carry one explicit ephemeral `authorizedForwardDedupKey` from the reviewed entry boundary through the shared contact leg, fresh coordinator, repository, DB helper, and exact-authority re-read. Null means the exact external shape; a nonblank value means the parent must be forwarded and its dedup key must equal that value. Received-direct and group/announcement paths set it only after their source snapshot gate succeeds. The direct-library path receives it only through the trusted strict application port after `DirectMediaBatchForwardDeliveryCoordinator` revalidation; generic provenance, attachments, `isForwarded`, or a test override alone are not authority.
- Generalize the existing fresh request/repository/DB/authority-read predicate to exactly two parent shapes: marker-free external (`authorizedForwardDedupKey == null`, `!isForwarded`, `dedupKey == id`) and authorized internal forward (nonblank authorization token, `isForwarded`, exact token equality). Both retain timestamp/created-at equality, no quote/edit/delete/hide/read/transport/wire state, ordinary policy, exact recipient/sender, complete attachments, v110 intent, and v111 projection.
- Preserve the entry's existing dedup semantics instead of reminting or normalizing them: generic direct and group/announcement-origin forwards use their existing contact-scoped SHA-256 token; direct-library batch deliberately reuses one source item's base token across its contact fanout. Every target still gets fresh message, attachment, key, nonce, artifact, v110, v111, and v108 identities.
- Reuse Plan 348's authority-before-preview/network order, exact-winner/key compensation, authority-aware `failed` versus `queued` mapping, preview copy, progress hooks, foreground lease, strict coordinator, and v108 send completion. Reuse Plan 347's lifecycle/restart owner without a forward-specific retry record.

Must preserve:

- Marker-free external OS media remains the exact Plan 348 strict adopter -> TC-350-04 plus TC-348-01/03/05 sentinels.
- Selector false or incomplete runtime capability remains legacy before strict selection; after strict selection there is no legacy fallback -> TC-350-04.
- Existing source and target authorization, received-direct/group snapshot lifetimes, direct-library revalidation/fail-closed source read, private/view-once/disappearing restrictions, and source-row/file preservation remain unchanged -> TC-350-01/04 plus existing direct/group/direct-library source sentinels.
- Group/announcement destinations, text-only shares, external shares, posts, historical/no-intent rows, media mutations, and unrelated ordinary sends retain their existing owner -> TC-350-04.
- Picker and direct-library matrices retry only `failed`; a target with v111 authority is `queued` and is not resubmitted -> TC-350-03/04 and existing GMF-05/sparse-retry sentinels.
- `STRICT_NETWORK_OWNERS` remains exactly the Plan 347 sender coordinator and receiver ACK owner; the share coordinator may call the sender owner but may not inline strict wire/schema vocabulary -> source contract.

Hard `Do not`:

- Do not add DB v112, a table/column/index, a forward outbox, a second artifact owner, a retry queue, a scheduler, a relay/native/bridge action or kind, a rollout flag, a raw strict media helper, or a platform/device harness.
- Do not weaken the external canonical shape globally, derive the authorization token from the candidate parent or generic provenance inside `_sendToContact`/a lower fresh-owner layer, treat arbitrary provenance through generic `deliver()` as source authorization, preserve an uncleared `DirectForwardSourceAuthority` into strict selection, call the direct-library port without its upstream revalidation in a causal test, or let `sendToContactFn` stand in for production.
- Do not re-hash the direct-library token, stop contact-scoping generic/group forwards, reuse identities across targets, read/delete/mutate the source after its existing lease ends, or require original plaintext for restart.
- Do not redesign forwarding UI, progress, picker ownership, group delivery, blob retention, or notification presentation.

Deferred / accepted difference:

- Ordinary-media caption EDIT and delete-for-everyone need a separate mutation/lifetime plan because they cross v109 and v111 authority; Plan 350 covers only newly authored forwarded parents.
- Direct-library forwarding intentionally remains point-in-time revalidate-then-read rather than snapshot-leased. A missing or unreadable source before staging is `failed` with zero custody/network; after v111, the existing artifact is authoritative and recovery is source-free. Post-revalidation parent/policy/byte drift remains the existing Plan 249 TOCTOU limitation and is outside Plan 350; a new snapshot/lock framework is out of scope.
- Exceptional snapshot-disposal throws beyond the existing bounded delete/failure-registration path remain a Plan 249 snapshot-owner concern. Plan 350 proves normal disposal plus source-free recovery and contains only progress-observer throws; it does not swallow synthetic disposal exceptions or redesign the snapshot owner/scavenger. Any cleanup-owner change requires re-review.
- Protected/view-once and disappearing media retain their separate private lifecycle owners; group destinations, per-device fanout, historical promotion, aggregate quota/UX, authenticated activation, and release operations remain later GAP-N01 work.
- Dependency-wave full `host-all`, aggregate Android recovery, and consolidated iOS acceptance remain owned by the GAP-N01 wave/final rollout rather than this Dart-only adopter.

Dependencies:

- Plans 345/347/348 supply v110/v111/v108 publication, strict encrypted-blob custody, fresh-owner staging, exact retry, and default-off selection. Plan 350 may parameterize those owners but must not fork them.
- Plan 349 is an adjacent ordinary-text mutation owner and must remain unaffected.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-350-01 | Every reviewed internal media-forward entry that targets a direct contact publishes one complete forwarded parent + attachments + v110 + v111 before the first LAN or relay observation. Received-direct and discussion/announcement cases traverse their real source gates; the direct-library case traverses `DirectMediaBatchForwardDeliveryCoordinator.deliverInitial` and its revalidator before the trusted strict port. Two-target cases keep fresh target-owned identities, generic/group tokens remain contact-scoped, and direct-library tokens retain their intentional per-item fanout value. One local-peer case observes complete authority inside `sendLocalMedia`; strict success then creates the matching v108 owner. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-350-01a source-gated received and group-origin forwards publish custody before network`; `test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart::TC-350-01b revalidated direct-library cells publish custody before network`; existing `post-preflight missing or oversized source fails every cell with zero caption-only message` | Host application; temp canonical sources; production `_sendToContact`; existing recording application repositories for TC-350-01b with a narrow v111-stage recorder; TC-350-01a may reuse the existing real-SQLite share fixture but does not require a new fixture; upstream direct-library revalidation and LAN/relay first-network observers; no `sendToContactFn` | HEAD reaches legacy LAN/upload with no parent/v111 for every internal case -> GREEN LAN/relay first observations see the exact staged authority, supplied authorization token/forward identity, and no raw legacy upload; rejected revalidation performs zero stage/network. TC-350-02 owns the real-SQLite transaction proof. | Restore the external-only selector, move LAN/relay before fresh stage, bypass direct-library revalidation, derive authorization from provenance, re-hash/pool a token, or reuse sibling identities -> TC-350-01 red | Exact selector-on commands; both files are in `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and AUTO `feature-host-all`; share test also remains in `GROUP_TESTS`; no registration edit |
| TC-350-02 | Fresh staging accepts exactly the independently authorized forwarded-parent alternative and retains the exact external alternative. Null/missing authorization with a forwarded parent, blank/mismatched nonblank token, `isForwarded`/dedup crossed shapes, same-message winner with another token, quote/edit/private state, partial/colliding rows, or parent drift refuse atomically; exact winner/key-compensation semantics remain Plan 348's existing proof. Production and the real-DB fixture forward the optional token without dropping or deriving it. | `test/core/database/helpers/media_attachments_db_helpers_test.dart::TC-350-02a fresh blob owner requires exact independent forward authorization`; `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::TC-350-02b fresh forwarded repository requires exact authorization token`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::TC-350-02c production wires fresh forward authorization exactly once`; existing `TC-348-02a/02b/02c` | Host real SQLite plus existing recording secure-key store and production composition source fixture | HEAD has no token parameter and refuses every forwarded fresh parent -> GREEN exact authorized forward applies/idempotently adopts while invalid/crossed candidates change no parent, attachment, key, or v111 row and external remains green | Drop/derive/change the independent token at coordinator, repository, DB, bootstrap, or fixture; use a broad `isForwarded || dedup != null`; or alter Plan 348 winner/compensation -> TC-350-02 red | Focused command; helper/bootstrap AUTO `core-host-all`, repository AUTO `feature-host-all`; no migration or manual registration |
| TC-350-03 | Authority truth is causal at each boundary. Pre-commit refusal is `failed` with zero parent/v111/network. Exact forwarded commit followed by ambiguous repository/reconciliation results forces the share-level DB re-read and is `queued`; an exact recipient/token/`isForwarded`/ID/projection drift does not authorize and never legacy-falls back. A throwing progress observer after commit cannot replace a durable queued/sent result. After file-backed SQLite reopen and normal source-snapshot disposal/source loss, retry reopens the same artifact, preserves IDs, exact dedup token, `isForwarded`, recipient, and encrypted inner projection, and creates one matching v108 before protected inbox store; the foreground lease still defers lifecycle retry. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-350-03a internal authority reread distinguishes precommit commit ambiguity and drift`; `::TC-350-03b postcommit progress observer cannot replace durable result`; `test/features/share/integration/external_share_media_custody_recovery_test.dart::TC-350-03c committed internal forward survives source loss and restart with exact provenance` | Host real/file-backed SQLite + temp artifact/files + real retry owner + lease, commit/return, observer, and drift barriers; extend the existing recovery harness in place | HEAD never creates the internal v111 owner; its private re-read rejects forwarded state, a progress exception can escape, and recovery is absent -> GREEN only complete exact authority is queued, no post-authority observer failure becomes picker-owned failed, and restart needs neither source nor preview | Return queued unconditionally, skip/drift the exact re-read, let the UI observer throw escape, retry from plaintext, rebuild dedup/isForwarded, delete v111 on normal source disposal, bypass lease, or store inbox before v108 -> TC-350-03 red | Exact focused run; existing recovery file AUTO `feature-host-all`; share test already curated; no new test file/registration |
| TC-350-04 | Decision and preservation table: selector/capability off remains legacy; only an entry-authorized, source-gated ordinary media forward to a current direct contact selects strict; strict selection never falls back. Every negative runs selector-on with all unrelated capabilities present, production `_sendToContact`, and exactly one varied exclusion, then asserts its intended legacy or fail-closed outcome plus no v111. Generic forged provenance, uncleared/failed direct source authority, failed direct-library/group source revalidation, private/view-once/disappearing source, text-only, group destination, historical/no-v111, and unrelated lanes stay excluded. External Plan 348 remains strict. Source rows/files are unchanged, queued targets are not picker/direct-matrix retries, and strict ownership remains centralized. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-350-04 internal forward custody decision table varies one authority at a time`; revise `TC-348-05 external strict adopter decision table is exact` to remove its stale blanket internal exclusion; existing direct/group/direct-library source, sparse-retry, GMF-05, absent-v111, and `scripts/test/relay_media_custody_contract_test.sh` sentinels | Host real-capability application table, policy/source sentinels, and source shell | Preservation cases are GREEN on HEAD while exact authorized strict cases are absent -> GREEN only reviewed entries change owner; no negative can pass because support, selector, or production sender was accidentally absent | Select on generic provenance/media alone, vary multiple selector conditions, admit a group destination/private source, mutate source, resubmit queued, inline strict tokens, or change external behavior -> TC-350-04/source sentinel red | Exact preservation commands; existing tests are already curated/AUTO; source shell runs directly and remains registered for later aggregate custody gates |

### Test Notes

- TC-350-01 must exercise production `_sendToContact`; `sendToContactFn` bypasses the adopter and is valid only for unchanged UI/matrix sentinels.
- A direct-received case is eligible only after `captureForDispatch` succeeds and clears `directForwardSourceAuthority`; the test must not manufacture a provenance-only equivalent.
- The direct-library causal case must enter through `DirectMediaBatchForwardDeliveryCoordinator.deliverInitial`, force its real `revalidateForDispatch` boundary, and then reach the production strict port. `deliverDirectMediaBatchForwardStrict()` is a trusted post-revalidation application port, not the source-authority test boundary. Direct-library has no snapshot lease: a missing/unreadable source before staging fails with zero custody/network, while source loss after v111 recovers from the artifact. Do not claim this closes arbitrary post-revalidation drift.
- TC-350-01b proves entry-to-stage-to-network ordering and exact token/target identity only. Transactional refusal/winner/key-compensation remain TC-350-02; restart durability remains TC-350-03. Do not replace its existing recording harness with a second real-SQLite/recovery harness.
- The direct-library batch token exception is intentional: one source item retains its existing token across contact scopes, while message/attachment/blob identities remain distinct. Generic `deliver()` and group/announcement-origin paths retain contact-scoped hashing.
- `authorizedForwardDedupKey` is one nullable, ephemeral call parameter. It is supplied only by an already-reviewed entry boundary, is checked independently against the candidate parent at every fresh-owner layer, and is neither persisted nor a cryptographic capability. TC-350-02 adds only this forwarded-parent delta and refusal cases; it does not replay Plan 347/348's crypto, concurrent-preparer, key-compensation, or artifact-cleanup matrices.
- TC-350-03a must force the share coordinator's private authority re-read, rather than merely fail after a result has already reported `hasDurableAuthority`. Pair a pre-commit refusal with an exact commit whose repository result and reconciliation are both ambiguous; then drift one exact field to prove the read is not an unconditional `queued` shortcut.
- Progress observers are non-authoritative telemetry. Contain their throws at `_ShareBatchProgressTracker._emit` so they cannot replace a post-v111 `queued`/`sent` result. Snapshot disposal follows its unchanged bounded owner and is exercised only on its normal path.
- TC-350-03c extends the existing recovery file to reuse its real-file fixture and failure helpers. The historical filename is accepted to avoid a rename or duplicate harness.
- Causal adopter tests inject the existing constructor selector as `true`, so they remain strict during ordinary family gates without depending on a global Dart define. TC-350-04 separately proves the production default-off selector; the focused define remains useful for production retry/composition paths. No new selector or define is introduced.

## Implementation Steps

1. Snapshot `git status --short` and `git rev-parse HEAD`. Require baseline `f11a732568aa0c72c8d4ed8bfecd5b1348adf130` unless a separately authorized baseline commit lands first. Preserve every live pre-existing change: planning began with the two PRD documents, `info.plist`, and the macOS Xcode project dirty; concurrent Graphify outputs and `scripts/run_claude_docker.sh` also became dirty before handoff. Record their live diffs and do not reset, overwrite, or claim them. Add TC-350-01a first and retain its causal nonzero RED before production edits; then add the upstream direct-library TC-350-01b RED.
2. Introduce one private nullable `authorizedForwardDedupKey` (or an equivalently narrow named argument) in `DefaultShareBatchDeliveryCoordinator`. Read the reviewed operation token only at the received-direct and group/announcement contact entry legs after their existing snapshot gates, and at the trusted direct-library port reached by the sole production `DirectMediaBatchForwardDeliveryCoordinator` caller after revalidation. Pass that independent value through `_sendToContact`; leave generic provenance, test overrides, and group destinations outside it. Lower layers must not derive it from the candidate parent, provenance, or attachments. Do not create a direct-library snapshot owner.
3. Rename/neutralize only the Plan 348 private fresh-share helper names needed for shared use. Parameterize the existing parent/send fields with the exact authorized dedup token and `isForwarded`; preserve fresh per-target IDs, timestamp/created-at equality, preview callback, foreground lease, progress, LAN callback, strict relay owner, result truth, and fixed-identity `sendChatMessage` completion. Contain progress-observer throws at the existing telemetry boundary so a durable result cannot be overwritten; add no ledger or cleanup-owner change.
4. Thread the nullable authorization argument through `prepareAndUploadFreshMessage`, `FreshOutgoingDirectMediaBlobGenerationRepository.stageFreshOutgoingDirectMediaBlobGeneration`, `MediaAttachmentRepositoryImpl`, `dbStageFreshOutgoingDirectMediaBlobGeneration`, the private exact-authority re-read, production bootstrap, and the shared real-DB fixture. Null retains the exact Plan 348 external shape; nonblank requires `isForwarded` and exact candidate-parent dedup equality. Keep every other canonical check and Plan 348's exact-absence/winner/key-compensation behavior. Stop and re-plan if this needs a schema change, persisted kind/provenance, or another transaction owner.
5. Implement TC-350-02 through TC-350-04 by extending existing fixtures. Update TC-348-05's blanket internal-forward legacy assertion to the new entry-authorized boundary without weakening its external/capability/no-fallback assertions. Keep source/picker/matrix tests as preservation sentinels; do not add UI production code or another recovery harness.
6. Keep `STRICT_NETWORK_OWNERS` and `STRICT_SCHEMA_OWNERS` unchanged in `scripts/test/relay_media_custody_contract_test.sh`; update only its stale bounded-adopter prose/PASS receipt from “Plans 347 and 348” to “Plans 347, 348, and 350” if implementation touches it. Add no Go/native/relay test or Android binding build.
7. Run the focused, preservation, source, curated, and justified family gates below. Refresh Graphify exactly once after coherent code changes, reconciling with rather than resetting any live pre-existing graph diff. During implementation closure, update Plan 350, the index, and the GAP-N01 coverage receipts without changing the PRD target requirements or claiming activation/GAP-N01/release closure.

## Risks And Blind Spots

- Entry-derived authorization could be lost or manufactured in the shared sender -> TC-350-01/04 require every real entry, including the upstream direct-library revalidation boundary, and reject forged provenance/test-override selection.
- A broad canonical-predicate change could admit unrelated forwarded/private rows or regress external share -> TC-350-02 requires two exact alternatives at coordinator/repository/DB/re-read/bootstrap/fixture boundaries and atomic refusal for crossed tokens.
- Dedup behavior differs by caller -> TC-350-01 pins contact-scoped generic/group tokens and the unchanged per-item direct-library token while every target keeps distinct custody identity.
- Source lifetime differs by route -> TC-350-01/04 preserve the received/group snapshot lease and prove direct-library point-in-time revalidation plus missing/unreadable-source refusal without inventing a lease; TC-350-03 proves v111-only recovery after post-authority disposal/source loss. Plan 249's post-revalidation TOCTOU remains explicit.
- Repository ambiguity could bypass or trivialize the private exact-authority re-read -> TC-350-03a pairs pre-commit refusal with commit-plus-ambiguous-result and exact-field drift barriers.
- Post-commit telemetry could become picker-owned failure and duplicate work -> TC-350-03b makes a throwing progress observer a causal, contained fault; TC-350-03c retains failed-only retry ownership. Exceptional snapshot-owner failure is explicitly deferred rather than swallowed incompletely.
- Lifecycle / derived-state durability: real-file reopen reconstructs exact parent/attachment/v111 ownership and retry creates one v108 without original plaintext -> TC-350-03.
- Sibling-surface consistency: Plan 348 external share remains strict; selector-off, capability-missing, text/group/private/historical and Plan 349 mutations remain on their existing owners -> TC-350-04.
- Destructive-action side effects: no deletion is introduced; source snapshot disposal and source row/file/metadata preservation are asserted, while only existing candidate-artifact compensation may run before authority -> TC-350-02/04.
- Invariant re-verification under new transitions: source and target authority are rechecked at existing dispatch points, exact DB authority is re-read after ambiguous commit, and restart rechecks the exact projection -> TC-350-01 through TC-350-03.
- Gate inflation could hide overengineering -> DB v112, new owner/flag/protocol, Go/native edits, device/iOS proof, full per-plan `host-all`, UI work, or a new recovery framework is scope drift.

## Gate Cadence

- Per-plan closure: TC-350 focused causal/SQLite/recovery tests; exact source/picker/matrix/external-share sentinels; the relay-media ownership shell; completeness; host `1to1`; `core-host-all` because a shared DB helper/repository predicate changes; serial `feature-host-all` because the share/coordinator/recovery production family changes; analyzer, exact changed-file format, diff hygiene, and one Graphify refresh.
- Do not run `./scripts/run_test_gates.sh 1to1`; it would repeat unchanged Go/relay custody tails. Use `./scripts/run_host_test_gates.sh 1to1`.
- Do not run full `host-all` for Plan 350. Run `./scripts/run_host_test_gates.sh host-all` once after the remaining GAP-N01 custody dependency wave and once at final rollout/release closure.
- Shared tests outside feature/core globs: `scripts/test/relay_media_custody_contract_test.sh` and exact preservation files run directly. No new family gate, `classify_path`, selector define beyond the existing custody define, device scenario, Go parent, or manual registry row is needed.

## Acceptance Gates

```bash
# Snapshot; preserve the four unrelated dirty paths.
git status --short
git rev-parse HEAD

# First causal REDs before production edits; expect non-zero because internal
# direct-contact forwards still reach legacy network before v111 authority.
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'TC-350-01a source-gated received and group-origin forwards publish custody before network'
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart \
  --plain-name 'TC-350-01b revalidated direct-library cells publish custody before network'

# Focused selector-on DB/repository/composition/adopter/restart GREEN; expect zero failures.
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/share/integration/external_share_media_custody_recovery_test.dart

# Existing source, matrix, picker, external-share, and legacy-retry sentinels.
flutter test --concurrency=1 \
  test/features/conversation/application/build_received_media_forward_test.dart \
  test/features/conversation/application/build_direct_media_library_batch_forward_test.dart \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart \
  test/features/groups/application/group_media_forward_policy_test.dart \
  test/features/share/presentation/share_target_picker_wired_test.dart
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  --plain-name 'TC-347-08c absent-v111 partial legacy attempt never promotes to strict'
bash scripts/test/relay_media_custody_contract_test.sh

# Discovery, affected curated lane, and justified host families.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1

# Hygiene and one post-change architecture refresh.
flutter analyze
dart format --output=none --set-exit-if-changed \
  $(git diff --name-only --diff-filter=ACMR -- '*.dart')
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-350-01a reaches the first real LAN/legacy upload while the queried target has no complete parent/attachment/v110/v111 authority; TC-350-01b does the same only after the upstream direct-library revalidator admits the source.
- Green sentinel: external TC-348 behavior, received/group snapshot leases, direct-library revalidation/token/matrix retry, picker failed-only retry, absent-v111 nonpromotion, and the strict owner shell remain green.
- Pre-existing dirty tree / known failure: the two PRD documents, `info.plist`, and `macos/Runner.xcodeproj/project.pbxproj` were unrelated user-owned changes at planning start. Concurrent changes to the architecture graph outputs and `scripts/run_claude_docker.sh` appeared before handoff and are likewise outside Plan 350 unless the executor proves otherwise. Preserve all live diffs. No baseline test failure is accepted; expected causal RED is recorded separately.
- Environment blocker: none. This plan changes no schema, native/platform API, real relay, OS lifecycle, or device behavior, so host real-file SQLite is the correct closure tier.
- Scope drift: any migration, persisted forward kind/provenance, new retry/network owner, raw strict helper, private/group-destination adoption, Go/native change, device/iOS requirement, UI redesign, or source-reconstruction dependency stops execution for re-review.

- [ ] Every reviewed internal source family reaches complete target-owned v111 authority before foreground network through its real source gate and the production contact leg; one LAN observation is explicitly covered.
- [ ] The two canonical fresh-parent alternatives and every crossed/partial refusal are causal, atomic, and preserve Plan 348 winner/key semantics.
- [ ] Pre-commit refusal remains `failed`; commit/return ambiguity is resolved only by the exact share-level authority re-read and becomes `queued`; field drift cannot authorize.
- [ ] A post-authority progress-observer throw cannot replace the durable result; normal snapshot disposal and restart preserve exact forwarded identity and create one matching v108 without original plaintext.
- [ ] Source/target authorization, token semantics, multi-target isolation/progress, external behavior, picker/matrix ownership, excluded lanes, and strict owner allowlists remain green.
- [ ] Causal RED, focused GREEN, and representative selector/order mutation re-red are recorded.
- [ ] Completeness, host `1to1`, core, serial feature, analyzer, format, diff, and one Graphify refresh pass.
- [ ] Selector and both relay admissions remain default-off; no activation, GAP-N01 closure, device/iOS, full `host-all`, or standalone release claim is made.

## Handoff

- First causal RED commands: the exact TC-350-01a and TC-350-01b commands above.
- Preservation command: the focused preservation batch plus `bash scripts/test/relay_media_custody_contract_test.sh` above.
- Manual registration: none; modified test files retain current curated/AUTO ownership.
- Migration: none; DB v111 and the existing fresh v110/v111 transaction remain sufficient.
- Boundary closure: host application + real SQLite/filesystem recovery. Plans 346-348 own unchanged relay/native/device primitives; the GAP-N01 wave/final closure owns aggregate Android and consolidated iOS evidence.
- Dirty-tree handoff: preserve every live pre-existing path, including the original PRD/plist/Xcode edits and the later graph/script changes; Plan 350 must report only its own path set.
- Unresolved evidence: none inside the bounded slice. Selector/admissions activation, broader GAP-N01 modalities, Plan 249 source TOCTOU/snapshot-owner exceptional cleanup, and wave/release evidence retain their named later owners.

## Reviewer Findings

- Verdict: `ready` after two complete counterexample passes; core bet: `confirmed`; disposition: `execute`.
- The direct-library trust claim was corrected: its real authority boundary is upstream `DirectMediaBatchForwardDeliveryCoordinator` revalidation, while `deliverDirectMediaBatchForwardStrict()` is only the trusted application port. The plan preserves point-in-time behavior and does not invent a lock or snapshot owner.
- One nullable, ephemeral `authorizedForwardDedupKey` now carries reviewed entry authorization independently through the contact sender, fresh coordinator, repository, DB helper, exact-authority re-read, bootstrap, and fixture. It is not persisted or treated as cryptographic provenance.
- Causal coverage now includes a LAN-local first-network observation, upstream direct-library traversal, exact pre-commit versus ambiguous-post-commit authority truth, field-drift refusal, and a throwing progress observer. Default-off/excluded cases run with otherwise complete production capability so they cannot pass vacuously.
- Test economy is explicit: TC-350-01b extends the existing recording application harness only; TC-350-02 owns real-SQLite transaction/refusal/winner proof; TC-350-03 owns file-backed restart durability. Plan 347/348 crypto, key, artifact, and retry matrices are not duplicated.
- Exceptional snapshot-disposal hardening was rejected as scope expansion because safe handling belongs inside the existing Plan 249 snapshot owner. Plan 350 preserves normal disposal and source-free recovery and does not add or incompletely swallow a cleanup failure.
- Overengineering remains prohibited: no DB v112/schema, persisted forward kind, new owner/queue/scheduler/selector, raw transport helper, relay/native/bridge change, UI redesign, device/iOS leg, or per-plan full `host-all`.
- Review blind-spot hits for stale authority, rollback/commit ambiguity, sibling bypass, outer observer failure, lifecycle reconstruction, and test vacuity are represented by TC-350-01 through TC-350-04; remaining classes are clear, preserved, deferred with an owner, or N/A.

## Arbiter Decision

Execute this bounded Plan 350 contract as written in a separate implementation session. It adopts only already-authorized ordinary internal-media forwards whose destination is a direct contact, while reusing the existing v110/v111/v108 custody and retry machinery. It does not close GAP-N01, alter activation, or authorize media mutation/private/group-destination/fanout/device/iOS expansion. No implementation is part of this session.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-09 | execution not started | planning artifacts only | `$tdd-plan` + `$tdd-review`: `ready`; `bash scripts/test/relay_media_custody_contract_test.sh`: PASS | Source-grounded four-bundle contract, literal RED/GREEN/preservation gates, explicit deferred owners, and scope stops are specified | none; execution handoff is ready | implement in a separate execution session and append `EXECUTION_COMPLETED` only after closure |
