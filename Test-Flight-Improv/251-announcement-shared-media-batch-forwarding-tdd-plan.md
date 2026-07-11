# 251 - Announcement Shared-Media Batch Forwarding

Status: evidence-gated
Type: New Feature
Spec: free-text intent — forward a multi-message selection from an announcement media library only after album, caption, provenance, cap, retry, and destination semantics are explicit
Classification: evidence-gated
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | plan-specific `graphify-arch` query; `share_intent_model.dart`; `share_batch_delivery_coordinator.dart`; target picker/policy; plans 232/236/240/241 | `ShareIntent` has one text plus many file paths, and the current coordinator sends one message containing all processed attachments per target. It has no multi-source grouping, per-item caption, or item-level retry contract. | keep batch Forward out of plan 241 and record the missing product decisions |
| 2026-07-09 | Planner | direct/group marker and retry contracts; announcement source/destination authorization; library cursor/selection semantics | Reusing the picker is sound, but choosing album-vs-individual or caption/retry behavior in code would silently invent product semantics and could break provenance/dedup | make the decision ledger a stop gate, then test one accepted output model |

## Problem And Evidence

- Behavior to improve: a recipient selecting images/videos from several announcement messages in the plan-241 media library may need to forward that selection to allowed contacts/groups in one deliberate operation.
- Impact: without an explicit batch contract, implementation could collapse unrelated source messages into one album, concatenate captions, exceed delivery limits, duplicate successful sends on retry, or leak linkable source provenance.
- Confirmed current mechanism: `ShareIntent` at `lib/core/services/share_intent_model.dart:1` carries one optional `text` and a flat `filePaths` list; it cannot represent a caption or provenance per selected source item.
- Confirmed current mechanism: `DefaultShareBatchDeliveryCoordinator.deliver` at `lib/features/share/application/share_batch_delivery_coordinator.dart:163` preprocesses the flat list, loops targets, and calls one `_sendToContact`/`_sendToGroup`; each target branch builds one outgoing message with all processed attachments at `:279` and `:382`.
- Confirmed result gap: `ShareBatchDeliveryResult` reports sent/queued/failed per target and only an aggregate skipped-oversized count. It cannot say which source item failed, which output unit was queued, or what a retry should resend.
- Confirmed source scope: plan 241 adds a cursor-paged, multi-message announcement media selection but explicitly excludes internal batch Forward. Plan 240 owns single-source-message Forward, caption keep/remove/edit, target policy, and target-scoped privacy-safe operation keys.
- Confirmed destination contracts: plan 232 owns direct `isForwarded`/encrypted-inner provenance and retry rendering; plan 236 owns group `isForwarded`/encrypted-inner propagation. Neither decides how several source parents become output messages.
- Existing coverage: share coordinator tests prove preprocess-once and per-target upload; plan-240 tests prove source-vs-destination discrimination and failed-target retention for one source message. No test covers a multi-parent selection.
- Missing coverage: selection/order/cap, album-vs-individual grouping, empty-vs-one-vs-per-item captions, output-unit operation keys, per-item/target failure atomicity, partial retry, and source/announcement target policy for batch.
- Refuted findings: a flat `ShareIntent(filePaths, text)` is not itself a batch-forwarding product contract. Its existing one-message behavior is implementation evidence, not authorization to merge several source messages.
- Unresolved findings: every row in the Evidence Decision Ledger below. These choices change message count, visible captions, dedup identity, retry scope and user expectations, so they block implementation.
- Affected production, test, and gate files cannot be finalized until the ledger is accepted. Likely seams are a typed library batch-forward draft/result, plan-240 picker/coordinator adapter, announcement library selection UI, share/group integration tests, and `GROUP_TESTS` registration; no schema or Go protocol is justified.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Output grouping | one new album/message per target vs one output per selected source parent/item; mixed image/video ordering and recipient rendering | unresolved | no output-unit builder or delivery loop |
| Caption policy | always empty/new batch caption vs single selected caption vs per-item captions; editing/removal and accessibility copy | unresolved | no draft/picker text model |
| Selection cap | maximum item count, aggregate byte/budget policy, mixed-type rule and over-cap UI | unresolved | no bounded eligibility or performance acceptance |
| Selection order | tap order vs source chronological/library order and duplicate-parent/attachment handling | unresolved | no deterministic output or retry identity |
| Item failure atomicity | fail whole album/target vs skip ineligible/failed item with disclosure; oversized/missing/evicted/protected transitions | unresolved | no truthful result model |
| Retry granularity | failed targets, failed output units, or failed items; preservation of queued/sent successes across reopen | unresolved | no retry state machine |
| Provenance/idempotency | target+output-unit opaque key generation/storage and marker behavior without source identity leakage | unresolved | no safe direct/group handoff |
| Announcement destination policy | source announcement exclusion and eligibility of other announcement targets under current admin/key/membership state | unresolved | no exact target set or revalidation oracle |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Build an immutable `AnnouncementMediaBatchForwardDraft` from durable selected library attachment/message IDs, never caller-supplied paths. Re-load, scope to the exact source announcement, deduplicate, apply lifecycle/integrity/file eligibility, preserve the accepted order, and enforce the accepted count/byte cap before opening targets.
- Materialize the accepted output grouping explicitly. Each output unit records its ordered items and accepted caption representation; do not use flat `ShareIntent` if the decision requires per-item captions or multiple output messages.
- Reuse plan 240's target picker and send-time policy after recording the batch-specific announcement destination rule. Contacts remain active/unblocked; groups require active membership/key and current write authority; other announcement destinations can never bypass current admin validation.
- Generate opaque operation keys scoped to `(forward invocation, destination target, output unit)`, persist them across queued/failed retry, and keep them unequal across targets/units. Source group/sender/message/attachment IDs remain local lookup inputs and are absent from keys, payloads, markers and diagnostics.
- Reuse plan 232's direct marker/provenance and plan 236's group marker. Mint fresh outgoing message/attachment/blob IDs and destination-specific encryption for every target/output unit; never reuse incoming or sibling-target key material.
- Return a result shaped to the accepted failure/retry granularity and retain exactly the retryable failed selection. Sent/queued successes are never repeated by a retry action.
- Leave the source announcement messages, attachments, captions, bookmarks and files unchanged and emit no source-announcement publish/inbox operation.

Must preserve:
- Single-item/single-source Forward remains plan 240 and does not wait for this batch feature -> TC-251-01.
- Accepted Plan 241 library Save/Share/Bookmark/Clear/Delete remains independently complete and contains no hidden batch-forward assumptions -> TC-251-01/10.
- Direct and group marker privacy/legacy/retry semantics remain plans 232/236 -> TC-251-06/11.
- Announcement reader write denial and destination send-time authorization remain Flutter/Go sentinels -> TC-251-05/10.

Hard `Do not`:
- Do not implement this plan, add a batch Forward button, or extend `ShareIntent` while any ledger row is unresolved.
- Do not silently merge source parents, concatenate or discard captions, choose tap/chronological order, or select a cap/failure policy by developer preference.
- Do not expose source group/sender/message/attachment identity in operation keys, direct/group payloads, marker copy, diagnostics or target UI.
- Do not reuse outgoing IDs, blobs, encryption keys/nonces or operation keys across destinations/output units.
- Do not retry sent/queued successes, convert a partial result to global success, or claim an item was forwarded if its upload/send was skipped.
- Do not allow the source announcement as a destination unless the accepted policy explicitly permits it and current publisher authorization is independently revalidated; reader publication remains forbidden in all cases.
- Do not add a DB migration, new direct/group wire field, Go framing/topic/validator change, relay endpoint or new encryption primitive.

Deferred / accepted difference:
- Single-source-message Forward and caption keep/remove/edit are plan 240 and remain independently shippable.
- External OS multi-file Share is plan 227/241 and has chooser-presented semantics; it is not internal Forward and does not close this plan.
- If accepted retry durability requires new generic share-operation persistence, allocate it in a separately reviewed migration owner after a fresh ledger check; this evidence-gated plan reserves no version.

Dependencies:
- Accepted `Test-Flight-Improv/241-announcement-shared-media-library-batch-tdd-plan.md` supplies the scoped selection surface but no Forward behavior.
- Accepted `Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md` supplies single-source eligibility, picker/target policy, caption modes and announcement no-source-publish adapter.
- Accepted `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` and implemented/device-proven `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` supply direct/group markers, privacy and retry contracts.
- Product decisions in this plan's Evidence Decision Ledger are blocking dependencies.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-251-00 | Every grouping/caption/cap/order/failure/retry/provenance/destination choice is accepted before executable work starts | `Test-Flight-Improv/251-announcement-shared-media-batch-forwarding-tdd-plan.md::Evidence Decision Ledger` | planning evidence / product-security-messaging sign-off | HEAD evidence RED: all rows unresolved -> each row records accepted choice, owner, date, user copy and proof oracle | N/A — stop gate makes later mutations meaningful | manual plan-review gate; blocks every following row |
| TC-251-01 | Library multi-select exposes Batch Forward only for an accepted bounded eligible selection; one item still invokes plan 240 and existing plan-241 actions remain unchanged | `test/features/groups/presentation/announcement_media_batch_forward_test.dart::batch forward eligibility is bounded and preserves single item and library actions` | evidence-gated widget / library selection and action spies | HEAD has no batch action -> exact selection states/action routes match accepted cap; one-item route calls plan 240; Save/Share/Delete/Bookmark remain | show action over cap, route one item to batch, or hide a plan-241 action -> TC-251-01 red | `flutter test test/features/groups/presentation/announcement_media_batch_forward_test.dart`; AUTO plus `GROUP_TESTS`; blocked by TC-251-00 |
| TC-251-02 | Draft construction re-loads exact source-announcement rows, deduplicates and orders them, and rejects stale/missing/evicted/unverified/protected items per accepted atomicity | `test/features/groups/application/announcement_media_batch_forward_draft_test.dart::batch draft enforces scoped order cap and current item eligibility` | evidence-gated application host / mixed-group, duplicate, stale, lifecycle fixtures | HEAD draft absent -> exact accepted IDs/order/rejections and no raw-path trust | use caller path, leak another group, ignore stale policy, or exceed bound -> TC-251-02 red | `flutter test test/features/groups/application/announcement_media_batch_forward_draft_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-251-03 | Selected source parents/items become exactly the accepted album-or-individual output units and recipient-visible attachment order | `test/features/groups/application/announcement_media_batch_forward_grouping_test.dart::batch output grouping matches accepted album and source-boundary policy` | evidence-gated application host / several source parents with mixed attachments | HEAD has only one flat `ShareIntent` message -> exact output count/membership/order and recipient render descriptors match decision | collapse individual units, split an album, or reorder mixed media -> TC-251-03 red | `flutter test test/features/groups/application/announcement_media_batch_forward_grouping_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-251-04 | Empty/new-batch/per-item caption behavior matches the accepted policy without silent concatenation, mutation or source attribution | `test/features/groups/application/announcement_media_batch_forward_caption_test.dart::batch caption model preserves exactly the accepted empty and per-item semantics` | evidence-gated unit/application / captions containing empty, RTL, emoji and multiline text | HEAD flat intent has one text only -> exact editable values/output captions follow decision; sources remain equal | concatenate sources, copy first caption implicitly, or drop per-item edit -> TC-251-04 red | `flutter test test/features/groups/application/announcement_media_batch_forward_caption_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-251-05 | Picker and send-time revalidation return the exact accepted contact/chat/announcement target set and never let source/read-only announcement authority bypass | `test/features/share/presentation/announcement_batch_forward_target_policy_test.dart::batch forward target set and send-time announcement policy are exact` | evidence-gated widget/application / mutable contacts/groups/roles/keys/memberships | HEAD has no batch source policy -> expected targets exact at display and send; demoted/blocked/removed targets fail truthfully | use cached group, include blocked contact/source, or allow non-admin announcement -> TC-251-05 red | `flutter test test/features/share/presentation/announcement_batch_forward_target_policy_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-251-06 | Each target/output unit receives the correct direct/group Forwarded marker and a distinct opaque retry-stable operation key with no source identity | `test/features/share/application/announcement_batch_forward_provenance_test.dart::batch output keys are target unit scoped stable and source anonymous` | application host / two contacts, two groups, multiple output units, payload/log capture | HEAD batch provenance absent -> marker true; keys stable on retry, unequal across target/unit, and contain/equal no source fixture | derive from source ID, reuse across units/targets, remint on retry, or drop marker -> TC-251-06 red | `flutter test test/features/share/application/announcement_batch_forward_provenance_test.dart`; AUTO plus `GROUP_TESTS`; codec/schema proof inherited from 232/236 |
| TC-251-07 | Preprocessing is bounded and every target/output unit gets fresh outgoing IDs, blobs and destination-specific encryption while source material is unchanged | `test/features/share/application/announcement_batch_forward_delivery_test.dart::batch forwarding bounds processing and remints encryption per target output unit` | application host / real coordinator path with temp media and content-transforming bridge | HEAD batch contract absent -> process count/bound matches decision; every tuple is unique and source snapshot equal | hoist upload/key/id across target or output unit, or process unbounded history -> TC-251-07 red | `flutter test test/features/share/application/announcement_batch_forward_delivery_test.dart --plain-name 'batch forwarding bounds processing and remints encryption per target output unit'`; AUTO plus `GROUP_TESTS` |
| TC-251-08 | Missing/oversized/upload-failed items settle the accepted album/target atomicity and produce item/output-level truth without marking skipped content sent | `test/features/share/application/announcement_batch_forward_delivery_test.dart::item failure applies accepted atomicity and reports exact forwarded subset` | evidence-gated application host / deterministic item failure matrix | HEAD result is target-only -> exact accepted abort/skip behavior and result membership; no false sent item | skip silently, abort contrary to decision, or count missing item sent -> TC-251-08 red | `flutter test test/features/share/application/announcement_batch_forward_delivery_test.dart --plain-name 'item failure applies accepted atomicity and reports exact forwarded subset'`; AUTO plus `GROUP_TESTS` |
| TC-251-09 | Partial retry retains exactly failed targets/output units/items under the accepted granularity and never re-sends sent/queued successes across retry/reopen | `test/features/share/integration/announcement_batch_forward_retry_test.dart::partial batch retry is stable granular and exactly once for successes` | evidence-gated host integration / scripted fail-then-recover targets, durable operation fixture if approved | HEAD has target-only in-memory selection -> exact retry subset and stable keys/IDs/envelopes follow decision; success call counts stay one | retry all targets, remint operation key, or lose queued unit on reopen -> TC-251-09 red | `flutter test test/features/share/integration/announcement_batch_forward_retry_test.dart`; AUTO plus `GROUP_TESTS`; persistence proof required if decision promises reopen |
| TC-251-10 | Batch forwarding mutates no source row/file/bookmark/caption and emits destination commands only, never a source-announcement publish/inbox command | `test/features/groups/integration/announcement_media_batch_forward_source_boundary_test.dart::batch forward preserves source and emits only target discriminated events` | host integration / source snapshots, target/source command log | HEAD flow absent -> destination events exact, source events absent, all source snapshots equal | use source group as destination or mark/delete source rows -> TC-251-10 red | `flutter test test/features/groups/integration/announcement_media_batch_forward_source_boundary_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-251-11 | Legacy/non-forwarded direct/group messages, plan-240 single Forward and Go announcement authorization stay unchanged with no new wire/transport contract | `test/features/conversation/domain/models/message_payload_test.dart::forward marker is legacy-safe inner-only and carries media plus dedup`, `test/features/groups/application/group_message_listener_test.dart::GMF-08 live forwarded marker roundtrips with legacy false fallback`, `test/features/groups/presentation/announcement_received_media_forwarding_test.dart::reader opens Forward picker for verified media while announcement compose remains read-only`, and `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` | GREEN sentinels / direct/group codecs, widget and Go validator | GREEN after dependencies -> remain GREEN; no DB/Go protocol edit expected | default legacy marker true, route one item to batch, or weaken writer auth -> sentinels red | `flutter test test/features/conversation/domain/models/message_payload_test.dart --plain-name 'forward marker is legacy-safe inner-only and carries media plus dedup' && flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'GMF-08 live forwarded marker roundtrips with legacy false fallback' && flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only' && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestIsAllowedWriter_AnnouncementMemberBlocked -count=1)`; existing gates |

### Test Notes

- TC-251-03/04 must assert recipient-visible output units/captions, not only the draft object. The accepted model determines whether one or several send calls are expected.
- TC-251-06 keys are opaque local/internal provenance, not a hash of source IDs. The fixture must compare against every source value and capture encrypted-inner/outer/log fields separately.
- TC-251-08/09 require event discrimination at target + output-unit + item granularity selected by the ledger. A single aggregate success/failure count is insufficient.
- If the accepted retry promise survives app restart, TC-251-09 cannot use an in-memory fake as closure; the plan must be refreshed with an exact migration/persistence owner and real reopen proof before execution-ready status.

## Implementation Steps

1. Resolve every Evidence Decision Ledger row with product/security/messaging owners, exact user copy and test oracle. Keep status evidence-gated and make no production/test/schema edits until then.
2. Reinspect the accepted plan-232/236/240/241 contracts and current migration ledger. If retry needs new persistence, assign it to a separately reviewed owner and refresh this plan before code. Stop-if any owner/semantic remains unresolved.
3. Snapshot `git status --short`; add TC-251-01 through TC-251-11 causal tests/sentinels around the accepted output model.
4. Add typed selection/draft/output-unit/result models that re-load current rows, enforce bounds and carry no transport-facing source identity. Do not overload flat `ShareIntent` if it cannot express the accepted caption/grouping model.
5. Extend the existing picker/coordinator through plan-240 adapters, revalidating target policy and generating stable target+unit operation keys; reuse plan-232/236 marker/wire contracts.
6. Implement the accepted failure/retry granularity with per-item/output/target truth and exactly-once preservation for successes. Stop-if durable claims lack real persistence/reopen proof.
7. Register new headline suites in `GROUP_TESTS`; run focused GREEN, dependency/authorization/transport sentinels, named host gates, analyzer and diff hygiene.

## Risks And Blind Spots

- Silent album/caption invention changes recipient meaning -> TC-251-00/03/04 block until product semantics are explicit.
- Large selections can cause memory, upload and UI stalls -> TC-251-01/02/07 enforce the accepted cap and bounded preprocessing.
- Partial upload/send can lie about what arrived -> TC-251-08 returns exact item/output membership.
- Retry can duplicate successes or break dedup by reminting provenance -> TC-251-06/09 lock scoped stable keys and exactly-once success calls.
- Target policy can stale between picker and send -> TC-251-05 re-loads contact/group role/key/membership.
- Lifecycle / derived-state durability: selection eligibility is reloaded at draft and send; retry durability is TC-251-09 or remains explicitly unaccepted if no persistence owner.
- Sibling-surface consistency: TC-251-01 preserves plan-240 single Forward and plan-241 library actions while adding only the accepted multi-select entry.
- Destructive-action side effects: N/A — forwarding is non-destructive; TC-251-10 snapshots every source row/file/bookmark/caption.
- Invariant re-verification under new transitions: TC-251-02/05/08 recheck source eligibility, target authority and item availability after selection.

## Acceptance Gates

```bash
# Evidence stop: do not continue while any batch-forward decision is unresolved
! rg -n '\| unresolved \|' Test-Flight-Improv/251-announcement-shared-media-batch-forwarding-tdd-plan.md

# Dependencies and dirty-tree snapshot
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/241-announcement-shared-media-library-batch-tdd-plan.md
git status --short

# First causal RED after evidence acceptance; expect non-zero because batch draft/output semantics are absent
flutter test test/features/groups/application/announcement_media_batch_forward_draft_test.dart

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/presentation/announcement_media_batch_forward_test.dart test/features/groups/application/announcement_media_batch_forward_draft_test.dart test/features/groups/application/announcement_media_batch_forward_grouping_test.dart test/features/groups/application/announcement_media_batch_forward_caption_test.dart test/features/share/presentation/announcement_batch_forward_target_policy_test.dart test/features/share/application/announcement_batch_forward_provenance_test.dart test/features/share/application/announcement_batch_forward_delivery_test.dart test/features/share/integration/announcement_batch_forward_retry_test.dart test/features/groups/integration/announcement_media_batch_forward_source_boundary_test.dart

# Single-forward/library preservation and native publisher authorization
flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart test/features/groups/presentation/announcement_media_library_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# No new transport/schema owner in this plan; compare against execution baseline
git diff --exit-code -- go-mknoon go-relay-server lib/core/database/migrations

# Named host gates; expect new files selected and zero failures
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-251-00 currently fails because every batch semantic row is unresolved. No production/test/schema action is authorized.
- Expected first executable RED after evidence: TC-251-02 compile-fails because no batch draft exists; TC-251-03/04/08/09 have no accepted implementation/result model.
- Green sentinels: plan-240 single Forward, plan-241 non-forward library actions, plan-232/236 legacy markers/retries, and Go publisher authorization remain green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: none for a host-only adapter after decisions, unless accepted retry semantics require durable persistence; then missing migration/reopen evidence blocks closure.
- Scope drift: developer-chosen grouping/caption/cap/retry, source-derived provenance, source publish, new marker/wire/Go behavior, or unowned schema blocks completion.

- [ ] Evidence Decision Ledger records accepted owner/date/user wording/test oracle for every row.
- [ ] Every selected behavior has a named causal test and representative mutation re-red.
- [ ] Output count/grouping/order and recipient-visible captions match the accepted model exactly.
- [ ] Selection bound, stale item policy, target revalidation and item/output/target results are truthful.
- [ ] Target+output operation keys are opaque, distinct, retry-stable and source-anonymous; IDs/encryption are fresh.
- [ ] Sent/queued successes are never retried and any promised restart durability has real persistence proof.
- [ ] Source state/events, single Forward, library actions, direct/group legacy markers and Go authorization are preserved.
- [ ] New files are registered in `GROUP_TESTS` and selected by named gates.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-251-00 is unresolved. After acceptance: `flutter test test/features/groups/application/announcement_media_batch_forward_draft_test.dart`.
- Preservation command: `flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart test/features/groups/presentation/announcement_media_library_test.dart`.
- Manual registration: after evidence approval, add the nine new batch-forward host files to `GROUP_TESTS`; AUTO feature discovery also selects them.
- Migration: none reserved. If accepted restart retry needs persistence, stop and assign/freshly conflict-check a separate migration owner before refreshing this plan.
- Boundary closure: host-only composition over accepted plan-232 direct and plan-236 group wire/retry proofs; no new Go/libp2p boundary.
- Unresolved evidence: output grouping, caption model, cap/order, item atomicity, retry granularity, provenance/idempotency, and announcement destination policy.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | evidence gate | plan only | source/graph audit complete | flat share/coordinator limits confirmed | Evidence Decision Ledger unresolved; no implementation authorized | product/security/messaging review |
