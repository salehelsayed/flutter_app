# 348 - GAP-N01 Ordinary Direct External-Share Media Blob Custody Adoption

Status: **IMPLEMENTED / DEFAULT-OFF CODE-CLOSED / PLAN-GREEN / HOST GATES GREEN / NOT STANDALONE RELEASE-ELIGIBLE** (2026-08-09)
Type: Modification
Baseline: `9d344e3867e8ee253a393fcadb43f1ef9a76b160` (`feat: adopt direct media blob custody`), including `Plan 347 — EXECUTION_COMPLETED`
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5 requirements 1, 3, and 6 plus A-01/A-02/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01
Classification: new behavior, bounded downstream adopter of the existing v110/v111/v108 ordinary-direct custody owner
Closure tier: host-only causal and real-SQLite proof, exact preservation sentinels, the host-only curated `1to1` lane, concurrent `feature-host-all`, and concurrent `core-host-all` because one shared DB helper changes. No DB migration, full `host-all`, Go/native/bridge/relay run, Android device run, or iOS run.

## Planning Progress

| Time | Role | Files inspected | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-08-08 | Evidence collection | GAP-N01/WP-01 report; Plans 345-347; external-share coordinator, picker, send/retry paths, real-DB fixture, source contracts, gate inventories | The real external contact leg still performs LAN/legacy upload before a durable message or v111 generation. `TC-347-08d` intentionally preserves that gap. | Keep Plan 348 to the external OS ordinary-direct adopter. |
| 2026-08-08 | Baseline audit | `STATUS.md`; Plan 347 plan and commit `9d344e386`; final v110/v111/v108 repository/coordinator APIs | Plan 347 is committed and code-closed. Its generation stage requires an existing parent and attachments, so one absent-parent transaction is unavoidable; no new schema is. | Re-anchor the plan to final symbols and tests. |
| 2026-08-08 | TDD planner | Graphify architecture query plus direct source/test/gate verification | Reuse `PreparedDirectMediaBlobCustodyCoordinator`, its artifact store, strict network owner, and existing retry. Avoid a share outbox, new scheduler, new transport owner, or duplicated device proof. | Run independent `$tdd-review`; apply only verified plan deltas. |
| 2026-08-08 | Independent TDD review | Core contract and boundary/reversibility passes over the first complete draft | Core bet confirmed, but production composition, dual-mode selector proof, canonical parent identity, post-authority truth, capability selection, secure-key ambiguity, exact-winner use, progress/publication order, and plaintext-preview wording required plan fixes. | Apply the bounded fixes; do not add a migration, queue, scanner, reconstruction path, transport owner, or device campaign. |
| 2026-08-08 | Final independent re-review | Revised plan, named tests, literal gates, and stop rules | Both reviewers returned `ready`; core bet `confirmed`; disposition `execute`; no user-owned decision or remaining blocker. | Append `Plan 348 — EXECUTION_READY`; implementation belongs to a later session. |

## Problem And Evidence

- The exact external-OS branch is selected only when both forward-authority fields are absent (`lib/features/share/application/share_batch_delivery_coordinator.dart:408-419`). `_deliverOrdinary` preprocesses once and then handles targets sequentially and independently (`:486-618`).
- `_sendToContact` currently allocates attachment IDs inside the upload loop, starts optional LAN, calls legacy `runUploadMedia`, and only then calls `sendChatMessage` without a fixed message identity (`lib/features/share/application/share_batch_delivery_coordinator.dart:1212-1341`). The first network side effect therefore precedes durable parent/v110/v111 authority.
- `_sendToContact` is shared by internal/direct-forward flows (`lib/features/share/application/share_batch_delivery_coordinator.dart:727-825`, `:990-1042`). The adopter predicate must be carried explicitly from the external entry branch; attachment presence alone is not authority.
- `DirectMediaBlobCustodyRepository.stageOutgoingDirectMediaBlobGeneration` and `dbStageOutgoingDirectMediaBlobGeneration` require the exact parent and attachment predecessor already to exist (`lib/features/conversation/domain/repositories/media_attachment_repository.dart:108-119`; `lib/core/database/helpers/media_attachments_db_helpers.dart:1267-1540`, especially the predecessor check at `:1459-1481`). They cannot publish a fresh external-share owner atomically.
- `PreparedDirectMediaBlobCustodyCoordinator.prepareAndUploadFresh` is already the sole sender-side strict network owner and publishes the exact encrypted generation before LAN/relay (`lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart:83-149`, `:241-347`, `:421-566`). Retry reopens v111 and never needs the original source (`lib/features/conversation/application/retry_incomplete_uploads_use_case.dart:518-559`, `:682-713`, `:1075-1146`).
- `PreparedDirectMediaBlobUploadResult.refused` does not currently prove that no durable generation exists because the coordinator catches post-stage exceptions as `refused` (`lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart:126-148`). The picker retries only `failed` targets and removes `queued` targets (`lib/features/share/presentation/screens/share_target_picker_wired.dart:412-443`), so a false `failed` after commit can create a second logical message.
- Existing tests already prove Plan 347 byte identity, strict retry, lease behavior, selector-off external legacy behavior, and generic picker failed-only retry. Plan 348 must test only the new external caller, absent-parent transaction, result ownership, and recovery boundary.

## Graph Grounding Snapshot

- Query: `python3 graphify-arch/tdd_context.py query "Plan 348 external OS share ordinary direct media ShareBatchDeliveryCoordinator PreparedDirectMediaBlobCustodyCoordinator prepareAndUploadFresh DirectMediaBlobCustodyRepository stageOutgoingDirectMediaBlobGeneration parent attachments v110 v111 before network retry queued failed MediaRepositoryRealDbFixture ONE_TO_ONE_TESTS feature-host-all core-host-all" --profile tdd --budget 700`.
- Result: `confidence=anchored`, `freshness=current`, fingerprint `44c28d47c9ae7151`.
- Anchors included `ShareBatchDeliveryCoordinator`, `prepareAndUploadFresh`, `MediaRepositoryRealDbFixture`, and `ONE_TO_ONE_TESTS`. Load-bearing claims were then checked in the final Plan 347 source.
- This planning/review session does not refresh Graphify. Implementation refreshes `graphify-arch` once after one coherent code change.

## Scope Contract And Guard

In scope:

- External OS share intents containing media, with no `forwardProvenance`, no `directForwardSourceAuthority`, and an ordinary direct-contact target.
- One independent message ID, timestamp, complete attachment-ID manifest, v110 intent, prepared attachment projection, and complete outgoing v111 generation per eligible target before that target's first network request.
- One optional capability, `FreshOutgoingDirectMediaBlobGenerationRepository`, with an independent `supportsFreshOutgoingDirectMediaBlobGeneration` predicate and `stageFreshOutgoingDirectMediaBlobGeneration`; `MediaAttachmentRepositoryImpl` backs it with `dbStageFreshOutgoingDirectMediaBlobGeneration`. This is an absent-parent entry into the existing owner, not a new owner or schema, and it must not widen Plan 347's existing `supportsDirectMediaBlobCustody` predicate.
- One new `PreparedDirectMediaBlobCustodyCoordinator.prepareAndUploadFreshMessage` entry point that reuses the existing artifact preparation and strict upload implementation.
- Production composition of that optional DB capability in `production_application_bootstrap.dart`, with the existing real-DB fixture wired separately and a source-contract assertion preventing a test-only adapter.
- One optional constructor selector on `ShareBatchDeliveryCoordinator`, defaulting to `kDirectMediaBlobCustodyClientEnabled`. This keeps production compile-time/default-off behavior while allowing selector-on causal tests to remain non-vacuous in default-off family gates.
- An explicit, non-persisted `hasDurableAuthority` result fact. It becomes true only after the fresh transaction inserts or re-reads an exact complete winner and remains true across every later copy/upload/send ambiguity.
- Existing global retry and `mediaUploadInFlightTracker` ownership. Durable-but-incomplete work is `queued`; only a target with no durable owner is `failed`.
- The current `currentContact ?? suppliedContact` external-share policy, preprocess-once behavior, sequential target isolation, progress reporting, and sent/queued/failed picker semantics.

Out of scope:

- Text-only external share; internal/direct forwards; groups/announcements; private/protected/view-once/disappearing media; posts; historical/no-intent rows; edits/deletes; or linked-device fanout.
- A share outbox, retry worker, scheduler, batch-wide transaction, cross-action dedup key, target parallelism, resumable chunks, or a second encryption/artifact/network owner.
- DB v112 or any migration, new table, wire/protocol action, Go/native/bridge/relay change, capability negotiation, production activation, rollout cohort, quota/UX work, or legacy retirement.
- Repeating Plan 347's byte-level crypto matrix, concurrent-generation matrix, Android binding/device campaign, or any iOS harness/device work.
- Reconstructing a sender-local plaintext preview from v111, making the pending-file copy atomic, or adding a pending-plaintext orphan scanner. v111 ciphertext is the custody/retry authority; a post-authority copy failure/crash may leave the sender-local preview missing, partial, or otherwise unusable, which is an accepted limitation of this bounded adopter.
- UI redesign. Existing picker behavior is a preservation sentinel; change picker production code only if a causal test proves its generic result handling is insufficient.

Hard `Do not`:

- Do not infer the adopter inside shared `_sendToContact` from media presence. Carry an explicit external-ordinary-direct eligibility fact from `deliver`.
- Do not call raw strict media helpers from `features/share`; `PreparedDirectMediaBlobCustodyCoordinator` remains the sole sender network owner.
- Do not start foreground LAN, strict relay upload, envelope send, or inbox store before complete v110/v111 authority commits. Attempt the canonical pending-plaintext copy before foreground network; if it fails, return `queued` without foreground network. Existing restart retry may upload/send from v111 without that plaintext copy.
- Do not fall back to legacy upload after strict selection or after a strict request may have committed.
- Do not return `failed` after durable authority exists, even when a repository/coordinator/send dependency throws or the coordinator returns `refused`; re-read exact authority when the result is ambiguous, then leave owned work to existing retry as `queued`.
- Do not copy the processed plaintext into durable storage before DB authority. This avoids adding a new plaintext-orphan scavenger. Never delete or overwrite the OS/preprocessed source.
- Do not restore a secure-key snapshot merely because a stage wrapper or result hydration threw. Re-read the exact DB winner under the lifecycle lock first; preserve winner-owned keys and authority, and compensate only when no exact complete winner exists.
- Do not publish a losing generation's key, attachment projection, or artifact after an idempotent winner is adopted; use only the returned winner projection and clean/compensate the loser through Plan 347's existing lifecycle rules.
- Do not weaken the predecessor CAS used by composer/voice or teach generic retry to mint missing v111 rows.
- Do not add a migration or persistent state merely to make external share structurally symmetric with another producer.

### Exact adopter decision table

| Entry state | Plan 348 path |
|---|---|
| Selector false | Existing legacy external-share behavior. |
| Selector true + marker-free external OS intent + media + ordinary direct target + complete repository/coordinator capabilities | Strict fresh-owner path. |
| `supportsFreshOutgoingDirectMediaBlobGeneration == false`, existing strict-custody support false, or another required capability missing before strict selection | Existing legacy behavior; create no strict candidate. Interface type membership alone is insufficient. |
| Strict path selected or attempted | Never fall back to legacy, regardless of later refusal or ambiguity. |
| Ordinary external target resolved by `currentContact ?? suppliedContact` | Eligible when the resolved contact satisfies the existing peer/key policy. |
| `useSuppliedContact: true` direct-batch forward, provenance/authority-bearing forward, group/announcement, text-only, private/protected/view-once/disappearing, post, or historical lane | Excluded; preserve its current owner and behavior. |

## Minimal Behavior And Storage Contract

For each eligible direct-contact target:

1. Resolve the contact exactly as today and apply the decision table before strict file, DB, or network side effects. Strict selection requires both independent runtime predicates—`supportsFreshOutgoingDirectMediaBlobGeneration` and existing `supportsDirectMediaBlobCustody`—plus the other required capabilities; interface type membership is insufficient. Missing strict capability is legacy only at this preselection boundary.
2. Allocate the fixed message ID, one UTC timestamp, complete unique attachment IDs, canonical `pending_uploads/<message>/<attachment>` projections, and v110 intent. The fresh parent must be the canonical ordinary outgoing projection: exact sender/recipient, `id == dedupKey`, shared `timestamp == createdAt`, exact caption/text, `status == sending`, ordinary policy/state, `isForwarded == false`, exact v110 manifest, and null pre-envelope transport/wire/relay/custody-completion fields. Claim all attachment IDs through `mediaUploadInFlightTracker` before publication; lease refusal creates no owner and performs no strict network work.
3. Encrypt from the shared processed source and persist the existing identity-scoped v111 artifact candidates. Under the existing media-custody lifecycle lock and secure-key snapshot/compensation path, atomically insert the absent parent, complete direct-owned `upload_pending` attachment projection, v110 intent, and complete outgoing-prepared v111 rows. The helper either inserts all rows, returns an exact complete winner, or refuses with no partial DB authority; the DB stage itself emits no premature message-change event.
4. Treat only the returned/re-read complete winner as authoritative. If the DB call, wrapper, secure-store read, or hydration throws after a possible commit, re-read the exact parent/attachment/v110/v111 tuple under the lifecycle lock before compensation. Preserve and return the winner's attachment/key/artifact projection when it exists; restore candidate key snapshots and clean loser artifacts only when no exact complete winner exists. A narrow fresh-stage/result value may carry a complete winner or authority-only outcome, but it must not create another persistent state machine.
5. After authority exists, attempt `MediaFileManager.copyToDurableStorage` for every processed source and verify the returned canonical path before this foreground leg enters LAN/relay. Normal success therefore publishes the final outgoing message only after source-equivalent pending files exist with direct ownership. A copy refusal/failure returns `queued`, performs no foreground network or immediate outgoing publication, and never revokes v111; a crash or throw may leave no preview or a partial/unusable canonical file, but that file is never custody authority. Process restart may upload/send from v111 without the original source or a verified complete local preview.
6. Reuse the coordinator's existing `onGenerationReady` LAN acceleration and strict relay upload, passing only the authoritative winner artifact; LAN failure cannot suppress relay. On completion, call `sendChatMessage` with the fixed message ID/timestamp and exact completed attachment projection so existing v108 binding owns the envelope.
7. Keep the entire post-selection remainder inside an authority-aware catch. Report `sent` only at the current `sendChatMessage` success boundary. On any thrown/refused/retained ambiguity, use the known fact or exact DB re-read: complete authority means `queued`; proven absence means `failed`. The outer per-target catch must never convert a post-authority exception into picker-owned `failed`.
8. Release the foreground lease in `finally`. Existing lifecycle/bootstrap retry reopens the same winner v111 generation and may create only the one matching v108 owner; Plan 348 writes no share-specific retry record.

Each target owns a separate transaction and identity set. A later OS share action may create a new logical message because the OS intent exposes no stable cross-action identity.

## Test Contract

| ID | Behavior / invariant | Tier / fixture | Literal test target | Expected RED on baseline | Mutation / false-GREEN guard | Gate ownership |
|---|---|---|---|---|---|---|
| TC-348-01 | With the production selector, explicit define `true` makes external ordinary-direct media reach canonical parent/attachment/v110/v111 authority and a source-equivalent pending copy before the first LAN/relay observation; default-off compilation meaningfully asserts the unchanged legacy call instead of skipping. Normal strict success publishes one direct-owned outgoing message only after those pending files exist. The causal leg uses production `_sendToContact`, never `sendToContactFn`. | Host application with repository/file/publication/network observers | `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-348-01 external direct media follows production selector and publishes authority before network` | Selector-on baseline invokes LAN/legacy upload while parent/v111 are absent | Restore upload-before-stage, bypass production via the override, omit an attachment, publish before the pending copy, or make the default-off branch vacuous -> red | Focused; host `1to1` |
| TC-348-02 | The fresh helper inserts the canonical parent + complete attachments + v110 + v111 all-or-none, rejects partial/colliding state, and returns only an exact complete winner. Repository cases prove pre-commit rejection compensates candidate keys, while real-helper-commit-then-wrapper-throw and post-commit secure-store hydration failure re-read/preserve the winner before compensation; a losing candidate never publishes its key/artifact. Production bootstrap supplies the capability exactly once. | Host real SQLite plus recording/failing secure store and existing bootstrap source fixture | `test/core/database/helpers/media_attachments_db_helpers_test.dart::TC-348-02a fresh blob owner is canonical all-or-none and exact-winner`; `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::TC-348-02b fresh blob owner resolves commit ambiguity before key compensation`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::TC-348-02c production wires fresh blob stage exactly once` | No fresh-owner helper/capability or production binding exists | Null/mismatched dedup, split commits, partial/cross-recipient winner, compensate after a real commit, hydrate/publish loser state, or omit bootstrap binding -> red | Focused; `core-host-all`; `feature-host-all` |
| TC-348-03 | With selector injected `true`, a post-commit pre-write copy refusal returns `queued`, performs no foreground network/publication, and leaves no verified complete preview. After process-style repository recreation and original-source loss, existing retry reopens the same winner IDs/v111 artifact, defers to the foreground lease, then creates one matching v108 owner without reconstructing a preview. A separate assertion classifies a possible partial/unusable crash artifact as non-authoritative rather than requiring atomic copy or cleanup. | Host file-backed real SQLite + temp files + `MediaRepositoryRealDbFixture` + real retry owner | `test/features/share/integration/external_share_media_custody_recovery_test.dart::TC-348-03 committed external share survives unusable preview and restart` | External share has no pre-network durable owner and reports failed | Return failed after commit, treat local-file presence as custody proof, require/re-encrypt source/plaintext on restart, upload while the foreground lease is held, mint a second identity, or add a queue/reconstruction/scavenger -> red | Exact focused; auto `feature-host-all` |
| TC-348-04 | With selector injected `true`, three targets preprocess once, keep distinct identity/v111 authority, continue independently, and report one pre-commit `failed`, one authority-then-envelope-throw `queued`, and one `sent`. Assert exact `started`/`settled`/`sending` ordering and totals; the generic picker retries only failed and never resubmits queued. | Host application table plus existing picker sentinel | `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-348-04 external fanout preserves progress and authority truth`; existing `test/features/share/presentation/share_target_picker_wired_test.dart::GMF-05 picker retries failed only and leaves queued forward to durable retry` | Current target IDs exist only inside upload and the outer catch maps thrown post-upload work to picker-owned failed | Reuse a sibling ID/artifact, abort after target A, preprocess per target, omit/reorder progress hooks, let the post-authority throw escape, or keep queued selected -> red | Focused; host `1to1`; `feature-host-all` |
| TC-348-05 | The decision table is exact: selector false and an interface implementation whose independent fresh-support predicate is false both use legacy with zero strict candidate/DB/network work; selector-on marker-free ordinary external `currentContact ?? suppliedContact` with both support predicates is eligible; strict selection never falls back; `useSuppliedContact: true` direct-batch/provenance forwards, groups, text-only/private/historical lanes, and absent-v111 retry remain excluded. Strict network-owner allowlist stays unchanged. | Host preservation table plus source contracts | Existing `TC-345-05b`, `TC-347-08d external share remains legacy`, `TC-347-08c absent-v111 partial legacy attempt never promotes to strict`; add `test/features/share/application/share_batch_delivery_coordinator_test.dart::TC-348-05 external strict adopter decision table is exact`; retain `scripts/test/relay_media_custody_contract_test.sh` | Preservation is green before implementation; selector-on exact adopter and independent fresh-capability table are absent | Treat interface membership as support, alter Plan 347's existing support predicate, default selector on, infer from attachments, call raw helper from share, reject ordinary supplied-contact fallback, admit direct-batch forward, or fall back after strict attempt -> red | Exact preservation; source contract; host `1to1` |

### First Causal RED

Add only TC-348-01, using the production selector (not its constructor override), existing coordinator constructor, and repositories; do not import a future Plan 348 symbol into the first test. Under the explicit define it exercises the causal strict expectation; under ordinary default-off family compilation the same test takes and asserts the legacy expectation rather than returning early.

```bash
flutter test \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'TC-348-01 external direct media follows production selector and publishes authority before network'
```

Expected baseline result: the first LAN/legacy-upload observer finds no fixed parent or v111 generation. Retain that behavioral RED and later mutation re-red by restoring the old network-before-authority ordering.

## Implementation Steps

1. Record `git status --short` and baseline `9d344e3867e8ee253a393fcadb43f1ef9a76b160`; preserve unrelated PRD/Xcode changes. Add and retain TC-348-01 RED before production edits.
2. Add the independent `FreshOutgoingDirectMediaBlobGenerationRepository.supportsFreshOutgoingDirectMediaBlobGeneration` plus `stageFreshOutgoingDirectMediaBlobGeneration` and `dbStageFreshOutgoingDirectMediaBlobGeneration`; wire `MediaAttachmentRepositoryImpl`, `production_application_bootstrap.dart`, and the real-DB fixture. The fresh predicate is true only when the fresh closure and required existing v111 load/stage authority are present; do not change the meaning of `supportsDirectMediaBlobCustody`. Reuse current validation, lifecycle lock, secure-key snapshots, and compensation helpers, but resolve possible commit/hydration failure by exact DB re-read before compensation and return only the winner projection. Extend `production_application_bootstrap_phase_contract_test.dart`. Stop and re-plan if this cannot be one v111-compatible transaction without DB v112.
3. Add `PreparedDirectMediaBlobCustodyCoordinator.prepareAndUploadFreshMessage`. Share the current artifact-publish/upload private implementation; add the post-authority/pre-foreground-network copy callback and `PreparedDirectMediaBlobUploadResult.hasDurableAuthority`. Any internal post-stage exception/refusal must retain known authority or perform an exact re-read; preserve existing composer/voice/retry entry-point behavior. Stop if implementation requires a second artifact, strict network coordinator, persistent state, plaintext reconstruction, or scavenger.
4. Add an optional `ShareBatchDeliveryCoordinator` selector parameter defaulting to `kDirectMediaBlobCustodyClientEnabled`. Carry an explicit external-ordinary-direct adopter fact from `deliver` through `_deliverOrdinary` to `_sendToContact`, apply the decision table, and keep the strict branch's entire remainder inside an authority-aware catch. In that branch resolve/validate first, allocate all identities/canonical parent fields, claim the existing foreground lease, invoke the new coordinator entry point, and map every returned or thrown outcome by known/re-read durable authority. Leave `share_batch_delivery_coordinator.dart:1240-1302` as the selector-false/preselection-capability-absent/excluded legacy branch; never reach it after strict selection.
5. Build TC-348-02 through TC-348-05. Reuse `MediaRepositoryRealDbFixture`, existing retry owners, upload tracker, picker sentinel, and Plan 347 artifact store. Do not duplicate Plan 347's crypto-byte, concurrent-preparer, receiver, relay, device, or full cleanup matrices.
6. Keep `STRICT_NETWORK_OWNERS` unchanged in `scripts/test/relay_media_custody_contract_test.sh`. Narrow only stale external-share wording/schema guards so the reviewed coordinator adopter is permitted without permitting raw strict helpers under share/groups/posts. Make the existing bootstrap phase contract non-vacuously require the fresh DB binding exactly once.
7. Run focused/preservation/source gates, host-only `1to1`, concurrent `feature-host-all`, required `core-host-all`, analysis, exact changed-file format, and diff hygiene. Refresh Graphify once after coherent implementation; update plan/index/coverage receipts without claiming production activation or GAP-N01 closure.

## Gate Cadence

- Per-plan closure: TC-348 focused tests, exact selector/excluded-lane sentinels, source contract, completeness, host-only curated `1to1`, concurrent `feature-host-all`, and `core-host-all` for the shared DB helper.
- The explicit-define focused run proves the production selector-on branch. In ordinary default-off host family runs, TC-348-01 asserts the legacy branch while TC-348-03/04 inject selector true through the optional constructor; no selector-on causal test skips or returns early.
- Do not run `./scripts/run_test_gates.sh 1to1` for this adopter; it would repeat unchanged Go/relay media tails. Use `./scripts/run_host_test_gates.sh 1to1`.
- Do not run full `host-all`. Run it once after the GAP-N01 custody dependency wave and again at final rollout/release closure.
- No manual test registration is expected: existing share files are already in both host 1:1 inventories; the new integration file is auto-classified by `feature-host-all`. Run it directly during focused closure. If discovery does not classify it, add one exact registration and re-run completeness rather than duplicating it across arrays.

## Acceptance Gates

```bash
# Snapshot and causal RED.
git status --short
git rev-parse HEAD
flutter test \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'TC-348-01 external direct media follows production selector and publishes authority before network'

# Focused selector-on causal, DB, repository, and restart proof.
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/share/integration/external_share_media_custody_recovery_test.dart

# Exact preservation sentinels.
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'TC-347-08d external share remains legacy'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'TC-345-05b fresh direct media share enters insert-fresh custody without preparation token'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'GMF-05 picker retries failed only and leaves queued forward to durable retry'
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  --plain-name 'TC-347-08c absent-v111 partial legacy attempt never promotes to strict'
flutter test test/features/share/integration/outgoing_share_media_owner_viewer_test.dart

# Source/discovery and affected host families.
bash scripts/test/relay_media_custody_contract_test.sh
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4

# Hygiene and one post-implementation graph refresh.
flutter analyze
dart format --output=none --set-exit-if-changed \
  lib/app/bootstrap/production_application_bootstrap.dart \
  lib/core/database/helpers/media_attachments_db_helpers.dart \
  lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart \
  lib/features/conversation/application/retry_incomplete_uploads_use_case.dart \
  lib/features/conversation/data/repositories/media_attachment_repository_impl.dart \
  lib/features/conversation/domain/models/direct_media_blob_generation_result.dart \
  lib/features/conversation/domain/repositories/media_attachment_repository.dart \
  lib/features/share/application/share_batch_delivery_coordinator.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/share/integration/external_share_media_custody_recovery_test.dart \
  test/shared/fixtures/media_repository_real_db_fixture.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart \
  test/unit/dtr18_placement_closure_contract_test.dart
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Risks And Blind Spots

- **Post-commit exception misclassification:** `refused` alone can hide authority. TC-348-03/04 require `hasDurableAuthority` to survive every later exception and prevent duplicate picker resend.
- **Post-commit secure-key ambiguity:** a stage wrapper or hydration read can throw after SQLite commits. TC-348-02b requires an exact re-read before compensation and forbids a losing candidate from replacing the winner's key/artifact projection.
- **Shared `_sendToContact` bleed:** internal forwards call the same method. TC-348-05 requires an explicit entry-derived predicate and preserves all sibling lanes.
- **Filesystem/DB crash window:** writing plaintext before DB creates an unowned orphan. Foreground order is encrypted candidate -> atomic DB authority -> attempted/verified plaintext copy -> network. A failed/crashed copy queues this leg; restart is explicitly allowed to send from v111 with the sender-local preview missing. TC-348-01/03 enforce that bounded policy without a new scavenger or reconstruction path.
- **Selector false makes family tests vacuous:** TC-348-01 asserts both production-selector modes, while TC-348-03/04 inject selector true. Default-off host family runs therefore exercise both preservation and strict behavior.
- **Interface membership is not runtime capability:** the independent fresh-support predicate prevents a null fresh DB closure from selecting strict, without disabling Plan 347's already-valid composer/voice support. TC-348-05 fixes both sides of that boundary.
- **Test-only capability wiring:** the real-DB fixture and production bootstrap have separate constructors. TC-348-02c makes the production DB binding a named acceptance condition.
- **Multi-target aliasing:** preprocess-once sources are shared but authority is not. TC-348-04 requires distinct target-owned IDs/artifacts and continuation.
- **Vacuous adopter test:** `sendToContactFn` bypasses production `_sendToContact`. TC-348-01 forbids that seam and queries authority at the first real network observer.
- **Gate inflation:** any migration, raw strict share helper, new retry owner, UI redesign, device campaign, or Go/native/relay edit is scope drift and requires re-review.

## Execution Interpretation And Done Criteria

- Retained RED/GREEN: the exact selector-on TC-348-01 first failed because the old network call saw no durable parent/v111 authority, then passed after implementation. A post-GREEN mutation that exposed strict upload immediately before the fresh stage failed at the same authority assertion and passed again after restoration.
- Green sentinel: selector-off `TC-347-08d`, absent-v111 `TC-347-08c`, supplied-contact fallback, and generic picker `GMF-05` remain green.
- Pre-existing dirty tree: the two PRD documents and local `info.plist` / macOS Xcode project changes are unrelated; do not stage, revert, or overwrite them except the explicitly requested coverage-doc update.
- Environment blocker: none; this is host-only and no mobile target is a closure condition.
- Scope drift: DB v112, new persistent owner, raw strict helper under share, retry depending on the original source, or changed UI/native/wire behavior stops execution for re-plan.

- [x] TC-348-01 causal RED, GREEN, and network-before-authority mutation re-red are retained.
- [x] Each eligible target has one canonical parent (`dedupKey == messageId`)/attachment/v110/v111 authority before its attempted pending copy and foreground network; every proven no-authority partial/refusal sends nothing.
- [x] Real-commit wrapper/hydration ambiguity re-reads before secure-key compensation, adopts only an exact complete winner projection, and production bootstrap wires the fresh capability exactly once.
- [x] Post-authority copy/upload/send ambiguity is `queued`, never picker-owned `failed`; pre-authority refusal remains `failed`.
- [x] A normal strict success publishes only after source-equivalent direct-owned pending files exist; a failed/crashed copy may leave the sender-local preview missing, partial, or unusable without making it authoritative, revoking v111, or blocking restart.
- [x] Restart uses the same message/attachment IDs and v111 ciphertext to create one matching v108 owner without the original source, pending plaintext, reconstruction, or a share queue.
- [x] Foreground lease, progress-hook ordering/totals, multi-target identity/isolation, dual-mode selector behavior, ordinary supplied-contact fallback, and every excluded lane pass.
- [x] Focused/source/completeness, host `1to1`, concurrent feature, required core, analyzer, format, diff, and one Graphify refresh pass.
- [x] Production selector and both relay admissions remain default-off; full `host-all`, aggregate Android, consolidated iOS, activation/operations, remaining GAP-N01 lanes, and release eligibility remain open.

## Handoff

- First causal RED: the exact TC-348-01 command above failed because the first network observer found no durable parent/v111 authority; the implemented branch is green, and the restored network-before-authority mutation failed the same assertion before restoration.
- Manual registration: none; `completeness-check` classified 1,437/1,437 test files.
- Migration: none; current DB v111 is sufficient.
- Boundary closure: host-only application + real SQLite/filesystem. Plan 347 owns unchanged transport/device evidence; GAP-N01 wave/final closure owns aggregate Android and consolidated iOS.
- Release claim: Plan 348 closes only marker-free external OS media -> ordinary direct-contact adoption under the default-off selector. It does not close the composite media item, GAP-N01, or standalone release eligibility.
- Gate receipt: focused selector-on closure passed 140 tests; exact TC-348/preservation/viewer sentinels, the custody source contract, curated host `1to1`, concurrent feature (841 paths / 8,979 passes / 7 declared skips), concurrent core (404 paths / 3,204 passes), and full analysis (`No issues found`, 123.6s) passed. Exact format, diff hygiene, and Graphify are recorded in Execution Progress.

## Reviewer Findings

Independent `$tdd-review` verdict: **ready**. Core bet: **confirmed**. Disposition: **execute**. Two read-only reviewers re-ran after every required plan fix; neither found a remaining blocker or user-owned decision.

| Reviewed finding | Final disposition |
|---|---|
| A fixture-only fresh DB adapter could leave production unwired | Production bootstrap and its existing phase-contract test are explicit scope, test, format, and done-criteria owners. |
| Default-off family gates could make selector-on tests vacuous | TC-348-01 asserts both production-selector modes; TC-348-03/04 inject true through one optional constructor parameter. |
| A precreated parent could preserve a null/mismatched dedup identity | The canonical transaction and TC-348-02 require `dedupKey == messageId` plus the exact ordinary parent projection. |
| Outer target exception handling could convert committed work to picker-owned `failed` | The full strict remainder is authority-aware; TC-348-04 throws after authority and requires `queued`, same IDs, continuation, and no picker resend. |
| Ordinary supplied-contact fallback conflicted with excluding supplied direct forwards | The entry-derived decision table keeps `currentContact ?? suppliedContact` eligible for marker-free external share while excluding `useSuppliedContact: true` and provenance-bearing forward lanes. |
| Runtime capability could be confused with interface membership | The new optional interface has an independent `supportsFreshOutgoingDirectMediaBlobGeneration`; false support selects legacy with zero strict side effects and does not alter Plan 347's predicate. |
| SQLite could commit before a wrapper/hydration/key read throws | TC-348-02b requires exact DB re-read under the lifecycle lock before secure-key compensation and uses only the returned winner projection. |
| Requiring a guaranteed plaintext copy would force atomic-copy/reconstruction/scavenger scope | v111 remains sole custody authority. A pre-write refusal proves queued restart; partial/unusable crash output is explicitly non-authoritative and accepted without new infrastructure. |
| Progress and successful outgoing-file publication could regress invisibly | TC-348-01/04 name source-equivalent pending-file/direct-owner publication and exact progress-hook ordering/totals. |

Blind-spot hits B-2, B-4, B-5, B-6, B-7, and B-9 are resolved in the contract above. B-1 is limited to the existing reversible, default-off, same-schema owner; B-8 and B-10 are not applicable because this plan changes no native, relay, device, or cross-version boundary. Five behavior bundles are sufficient; broader Plan 347 crypto/concurrency/device matrices remain preservation evidence rather than duplicated Plan 348 work.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-08 | not started | plan only | independent final reviews: `ready` / core bet `confirmed` / disposition `execute` | planning and review complete; no production or test implementation performed | none | later implementation session starts with TC-348-01 causal RED |
| 2026-08-08 | RED | `share_batch_delivery_coordinator_test.dart` | exact selector-on TC-348-01 exited 1: first network observer found `authorityCompleteAtFirstNetwork == false` | causal legacy network-before-authority defect reproduced before production edits | none | implement the fresh transaction and strict external-share adopter |
| 2026-08-09 | GREEN + hardening | fresh repository/DB stage, coordinator, share adopter, retry preservation, bootstrap, fixtures, five behavior bundles, source/DTR contracts | selector-on focused set passed 140; TC-348 named set passed 7; explicit network-before-authority mutation exited 1 at the authority assertion, then restored exact TC-348-01 passed | canonical absent-parent authority, ambiguity compensation, preview/restart, fanout truth, exclusions, and bootstrap binding are causally covered | none | run closure families and hygiene |
| 2026-08-09 | host closure | affected app/test/source paths | source contract `PASS`; completeness 1,437/1,437; curated `1to1` `PASS`; concurrent feature 841 paths / 8,979 passes / 7 skips; concurrent core 404 paths / 3,204 passes; analyzer no issues in 123.6s | all requested host behavior and preservation gates are green; full `host-all` and mobile legs intentionally omitted | none | exact format/diff, affected-impact query, and one incremental Graphify refresh |
| 2026-08-09 | closure | 16 changed Dart paths plus architecture graph | exact format: 16 files / 0 changed; `git diff --check` green; affected query green; incremental Graphify: 17 changed code / 3,132 unchanged / 0 deleted, 70,157 nodes / 103,329 edges | every Plan 348 done criterion is satisfied; selector and both relay admissions remain default-off | none | implementation handoff complete |
