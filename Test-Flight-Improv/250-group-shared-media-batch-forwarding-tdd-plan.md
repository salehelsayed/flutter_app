# 250 - Group Shared Media Batch Forwarding

Status: evidence-gated
Type: New Feature
Spec: free-text intent — define and implement multi-selection forwarding from a discussion-group media library without inventing album, caption, provenance, or retry semantics
Classification: evidence-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | graphify-arch query, group media library plan/source, share picker/coordinator, group message media/send/retry paths, group forwarding plan, bridge/node extra handling and gates | Existing single-item plan 236 and share coordinator provide destination-scoped upload/send primitives. Multi-selection still lacks an accepted album-vs-individual, ordering/caption, identity/provenance, cap, and partial-retry contract. Plan 237 therefore keeps multi-select Forward absent. | Product accepts the batch semantics ledger; then choose host/device boundary and start the draft-builder RED. |

## Problem And Evidence

- Behavior to improve: after selecting multiple entries in a `GroupType.chat` shared-media library, a user may want to forward them to one or more contacts and writable discussion groups.
- Impact: plan 237 supplies safe multi-selection for Save/Share/Bookmark/Delete/Evict but intentionally omits internal Forward; plan 236 forwards exactly one selected item. Guessing how several source messages become destination messages can lose captions, reorder content, duplicate retries, or misstate provenance.
- Confirmed existing primitive: `DefaultShareBatchDeliveryCoordinator` already uploads attachments separately per target and invokes existing contact/group send use cases. Plan 236 constrains internal Forward to verified ordinary media, contact/`GroupType.chat` destinations, destination-current authorization, new attachment ids/ciphertext/access, and a backward-compatible forwarded marker.
- Confirmed representational option: group messages can carry a media list plus one message text/caption, so one destination album may be technically representable through existing media payloads. That does not decide how captions from several parent messages are preserved or whether one batch should instead emit individual messages.
- Confirmed provenance constraint: plan 236 intentionally stores only `isForwarded` and never copies original sender, source group, or source message identity. A multi-source album has one message-level marker, while individual sends have one marker per output; the product must define the expected truthful label without origin leakage.
- Confirmed ordering ambiguity: plan 228 library pages are newest-first, while human forwarding may expect tap-selection order or chronological source order. Equal timestamps require attachment/message identity tie-breaking.
- Confirmed retry ambiguity: an album has a per-target atomic send boundary but may have per-attachment upload failures; individual messages create a source-by-target result matrix. Retrying successful cells can duplicate messages, while retrying a partially uploaded album may leak abandoned blobs.
- Confirmed resource risk: there is no approved maximum item count, total bytes, per-file bytes, video duration, preprocessing policy, or preflight behavior for multi-source internal forwarding.
- Confirmed authorization race: destination membership/key/writability and source integrity/private state can change while the picker or a long batch is open. Eligibility needs an accepted revalidation/stop policy.
- Missing coverage: no batch-forward action, draft semantics, ordering/caption policy, selection cap, source-target identity matrix, per-target encryption assertion, partial retry contract, restart behavior, announcement guard, or real multi-item crypto proof exists.
- Refuted finding: invoking plan 236 once per selected item is not a neutral implementation detail. It chooses individual-message UX, caption handling, notification count, ordering, retry granularity, and recipient rendering without product approval.
- Unresolved findings that block implementation:
  - Output unit: one multi-attachment album per target or one message per selected source item; whether contacts/groups differ.
  - Stable ordering: explicit selection order, source chronological order, or library order; equal-time tie breaker.
  - Caption semantics: keep each source caption, one editable batch caption, first caption only, concatenate with limits, or no caption; album representation supports only one message text.
  - Provenance: message-level vs attachment-level display and idempotency while still forbidding original sender/group/message identity propagation.
  - Selection cap: count/total bytes/per-item bytes/video duration and whether ineligible entries are rejected individually or block the batch.
  - Partial results/retry: atomicity per target/album/source-target cell, retry selection, duplicate prevention, cleanup of uploads for a failed output, and app-restart behavior.
  - Destination authorization race: skip one target, halt all, or continue already-authorized targets when membership/key changes mid-batch.
  - Private/expired/evicted items and whether explicit redownload is allowed before batch submission.
- No migration or transport version is reserved by this evidence-gated plan.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Output unit | album-vs-individual decision for contact and discussion-group targets | unresolved | no batch draft/delivery loop |
| Ordering | exact input/output order and equal-time tie breaker | unresolved | no deterministic request model |
| Captions | preserve/edit/drop rules and length/normalization limits | unresolved | no composed output payload |
| Provenance/idempotency | output marker granularity and source-target delivery identity without origin leakage | unresolved | no safe retry/dedup key |
| Selection cap | count/bytes/duration limits and preflight/partial rejection UX | unresolved | no bounded resource contract |
| Partial retry | target/source/album success matrix, retry and orphan-upload cleanup | unresolved | no truthful result/retry UI |
| Authorization race | send-time and mid-batch target/source change policy | unresolved | no dispatch controller |
| Restart durability | route-local only or durable batch resume/cancel | unresolved | no persistence/migration decision |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Source is a bounded multi-selection of ordinary incoming verified image/video entries from one `GroupType.chat` library.
- Destinations reuse plan 236: contacts and writable `GroupType.chat` groups only. Revalidate each destination and each source at the approved dispatch boundary.
- Add multi-select Forward to plan 237 only after the accepted cap/draft/result contract is available; canceled picker/preflight changes nothing.
- Build a typed `GroupMediaBatchForwardDraft` whose ordered source identities, chosen caption policy, output grouping, destination set, and idempotency keys are explicit and immutable after confirmation.
- Reuse plan 236 for every actual output: new message/attachment ids, explicit forwarded marker, destination-specific upload/encryption/access, current authorization, no source mutation, and no original-author/source-conversation metadata.
- Model results at the approved atomicity boundary. Keep successful targets/outputs successful, retry only approved failures, and never label queued/partial work as fully sent.
- Preflight approved count/byte/duration limits before native decode/upload; stop or exclude ineligible items exactly as decided and disclose the result.
- Clean only batch-owned uncommitted temp/upload state according to the accepted failure policy; never delete source files/messages or a successful destination output.
- If durable batch resume is approved, allocate a freshly verified next free DB version at evidence refresh with structural host and production-SQLCipher device proof. Otherwise keep draft/results route-local and make restart cancellation explicit.

Must preserve:
- Plan 237 stays implementation-ready with no active multi-select Forward until this plan clears evidence.
- Plan 236 single-item forwarding, destination filters, v98 group marker, legacy false fallback, per-target encryption, narrow Go-bridge-only allowance, and no-origin policy.
- Announcement readers/admins and announcement destination rules remain unchanged; this plan is discussion-source/discussion-target only.
- Existing group send authorization, inbox/retry identity, media integrity, and source rows/files.

Hard `Do not`:
- Do not implement batch Forward, choose album/individual output, or reuse a loop of single-item forwards while the ledger is unresolved.
- Do not add a new group message type, album protocol, pubsub topic, outer routing field, recipient/fanout rule, retry protocol, group key rule, relay behavior, or Go node/libp2p production edit without an accepted transport expansion.
- Do not reuse source ciphertext/key/nonce/blob id/allowed peers across any target.
- Do not propagate original sender, source group/message ids, or per-source hidden metadata in marker, caption, diagnostics, or idempotency keys visible to recipients.
- Do not forward announcement/QA sources or targets, pending/failed/quarantined/missing/expired/consumed/protected media, or exceed accepted caps.
- Do not retry successful source-target outputs, delete successful destination messages, or call a partially completed matrix “sent.”
- Do not reserve a migration while restart durability is undecided.

Deferred / accepted difference:
- Single-item Forward remains plan 236 and is not blocked by this plan.
- Plan 237 multi-select Save/OS Share/Bookmark/Delete/Evict remains implementation-ready and independent.
- Album-specific visual layout, caption-per-attachment wire metadata, or a new protocol requires a refreshed implementation plan if the accepted decision cannot use the existing media-list message safely.
- Announcement batch forwarding requires a separate announcement policy owner.

Dependencies:
- Plan 236 group received-media forwarding and its v98/real-crypto closure.
- Plan 237 group shared-media library selection identities/capabilities.
- Plan 228 stable media-library identity/order and plan 230 typed selected-item viewer.
- Product decision for every Evidence Decision Ledger row.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-250-00 | No batch-forward code starts until output, order, caption, provenance, cap, retry, authorization-race, and restart decisions are accepted. | `Test-Flight-Improv/250-group-shared-media-batch-forwarding-tdd-plan.md::Evidence Decision Ledger` | planning evidence / product-security-engineering review | HEAD evidence RED: all rows unresolved -> each records accepted choice, owner/date, user copy, and proof topology | N/A — stop gate makes later tests causal | manual plan-review gate; blocks all following rows |
| TC-250-01 | Multi-select Forward appears only after an accepted bounded eligible selection; single-item behavior remains plan 236. | `test/features/groups/presentation/group_shared_media_batch_forward_test.dart::GBF-01 batch forward visibility follows approved selection and cap matrix` | evidence-gated host widget / eligible/ineligible count-byte-state table | HEAD GREEN sentinel from plan 237 says action absent -> after acceptance exact eligible rows expose it; invalid rows remain absent/disabled truthfully | show action before decision, exceed cap, or use first-item eligibility only -> GBF-01 red | add file to `GROUP_TESTS` after TC-250-00 |
| TC-250-02 | Draft grouping/order/captions exactly match the accepted album-or-individual contract under tied timestamps and multi-parent captions. | `test/features/groups/application/group_media_batch_forward_draft_test.dart::GBF-02 draft output units order and captions match approved contract` | evidence-gated host unit / selection-order, chronological, tied-id and caption fixtures | HEAD compile RED: draft absent -> exact output list/media grouping/text and immutable source identity order pass | switch order, drop/duplicate a caption contrary to policy, or group individual outputs -> GBF-02 red | add file to `GROUP_TESTS` |
| TC-250-03 | Preflight enforces approved count/total/per-item/duration limits and source eligibility without decoding/uploading rejected work. | `test/features/groups/application/group_media_batch_forward_preflight_test.dart::GBF-03 preflight is bounded fail closed and side effect free` | evidence-gated host application / metadata table + decode/upload spies | HEAD compile RED -> accepted reject/partial policy, reason/counts, and zero forbidden calls are exact | check limit after upload, overflow arithmetic, or silently drop item -> GBF-03 red | add file to `GROUP_TESTS` |
| TC-250-04 | Picker exposes contacts/writable discussion groups only and dispatch revalidates source plus destination according to the accepted mid-batch policy. | `test/features/groups/application/group_media_batch_forward_authorization_test.dart::GBF-04 destination and source changes follow approved dispatch stop policy` | evidence-gated host application / membership/key/group-type and source-state changes | HEAD compile RED -> exact continue/skip/halt results and zero unauthorized upload/send calls | accept announcement, trust picker-time auth, or continue a revoked target contrary to policy -> GBF-04 red | add file to `GROUP_TESTS` |
| TC-250-05 | Every output/source-target cell has stable opaque provenance/idempotency, is visibly forwarded, and reveals no original identity. | `test/features/groups/application/group_media_batch_forward_provenance_test.dart::GBF-05 provenance is stable per approved output and origin minimizing` | evidence-gated host unit/integration / retry and sentinel origin fixtures | HEAD compile RED -> approved ids/marker granularity remain stable on retry; sender/group/message sentinel values absent | mint retry ids, leave one output unmarked, or serialize origin -> GBF-05 red | add file to `GROUP_TESTS`; plan-236 marker sentinels remain green |
| TC-250-06 | Every attachment is uploaded/re-encrypted separately for each target with new ids and destination-current access; no source crypto crosses. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GBF-06 multi-source forward isolates encryption and access per target` | evidence-gated host integration / real temp sources + fake uploader/contact/group senders | HEAD lacks typed batch draft -> exact call matrix/new ids/keys/nonces/allowed peers and output grouping pass | reuse any crypto/blob/access metadata or use one target's peers for another -> GBF-06 red | existing share test AUTO; add named group registration if split |
| TC-250-07 | Partial result and retry operate only at the accepted target/source/album boundary, never duplicating successful outputs or leaking abandoned uploads. | `test/features/groups/application/group_media_batch_forward_delivery_test.dart::GBF-07 partial retry is idempotent and cleanup scoped at approved boundary` | evidence-gated host application / deterministic upload/send success, queue, timeout, failure matrix | HEAD compile RED -> exact result grid, retry calls, stable ids, cleanup and labels pass | retry success, collapse partial to success, orphan failed temp/blob, or delete committed output -> GBF-07 red | add file to `GROUP_TESTS` |
| TC-250-08 | Cancel, source mutation, route disposal, and approved restart behavior preserve source state and converge without unintended dispatch. | `test/features/groups/integration/group_media_batch_forward_lifecycle_test.dart::GBF-08 cancel mutation disposal and restart follow approved durability contract` | evidence-gated host integration / fresh controller/repository, temp sources, delayed picker/uploader | HEAD compile RED -> cancel zero calls; changed sources revalidate; disposal/restart state exact | dispatch after cancel/dispose, mutate source, or resume when policy says cancel -> GBF-08 red | add file to `GROUP_TESTS`; persistence proof conditional |
| TC-250-09 | Recipient rendering/notifications reflect the accepted output unit/order/caption and one truthful Forwarded indicator per output without origin details. | `test/features/groups/presentation/group_media_batch_forward_render_test.dart::GBF-09 destination output renders approved grouping order caption and marker` | evidence-gated host widget / contact/group output fixtures | HEAD no batch outputs -> exact message/media count, order/text/marker and notification count/copy pass after decision | render wrong grouping/caption/order or one marker per attachment contrary to policy -> GBF-09 red | add group-owned test to `GROUP_TESTS`; contact sentinel AUTO as required |
| TC-250-10 | Announcement/QA sources and targets stay excluded and their current writer/read-only rules do not change. | `test/features/groups/presentation/group_shared_media_batch_forward_test.dart::GBF-10 batch forwarding remains discussion only` | `GREEN sentinel` extension / chat, announcement reader/admin, QA fixtures | HEAD plan-237 action absent and announcement rules green -> only accepted chat flow changes | broaden group type or share picker target rule -> GBF-10 red | `GROUP_TESTS`; existing announcement sentinels |
| TC-250-11 | Chosen implementation uses only plan-236 existing delivery semantics unless a refreshed plan explicitly proves an approved album protocol change. | `test/features/groups/integration/group_media_batch_forward_transport_boundary_test.dart::GBF-11 batch forwarding introduces no implicit group transport change` | host source-contract / exact allowlist | HEAD compile RED: batch sources absent -> permits library/draft/coordinator adapters; forbids Go node/topic/auth/fanout/key/retry changes | add a wire/message type or call bridge directly -> GBF-11 red | add file to `GROUP_TESTS`; pinned Go/node sentinels |
| TC-250-12 | Real selected output survives destination encryption/decryption with the approved grouping/order/marker and no cross-target access. | `integration_test/group_batch_forwarding_crypto_proof_test.dart::GBF-12 approved multi-source output survives real encrypted group delivery` | external-fixture-blocked device proof / topology selected by album-vs-individual decision | HEAD evidence/device RED: no contract/file -> actual output count/media order/caption/marker decrypt correctly and unauthorized target cannot access | N/A until output unit selected; then reorder/drop attachment, wrong allowed peers, or marker loss -> GBF-12 red | add an exact `classify_path` `group/test` rule and group simulator entry if this dedicated proof is required |

### Test Notes

- TC-250-02 must include at least two selected attachments from different parent messages with different captions and identical timestamps; otherwise ordering/caption mutations can pass vacuously.
- TC-250-05 idempotency may derive from opaque batch/source/target ids internally, but recipient payload/diagnostics must not reveal original message/group/sender identity.
- TC-250-07's expected retry grid cannot be written until album-vs-individual atomicity is accepted; that is why the plan remains evidence-gated.
- TC-250-12 may reuse/extend plan 236's real-crypto fixture if the accepted solution only composes existing outputs. A new dedicated path still requires an exact discovery rule; no wildcard classifier exists.

## Implementation Steps

1. Resolve every Evidence Decision Ledger row with product/security/engineering owners. Keep plan-237 batch Forward absent and make no production/test/persistence/transport edits.
2. Refresh this plan with exact output model, state/result matrix, limits, captions, idempotency, file symbols, and device topology; if durable restart is approved, allocate a freshly verified next free DB version and add structural plus SQLCipher proof. Independently review the refresh.
3. Verify plans 236/237 have landed. Snapshot `git status --short`; add TC-250-02 as the first executable RED after evidence acceptance.
4. Add pure draft/preflight/provenance policies and multi-select UI capability before delivery; prove no origin leakage and deterministic bounds/order.
5. Compose only plan-236 destination-specific forwarding primitives at the accepted output boundary; implement truthful result/retry/cleanup without bridge/node shortcuts.
6. Add exact group device-proof classification if required, run real crypto plus host mutation/preservation/announcement/gate/analyzer/hygiene closure.

## Risks And Blind Spots

- Album-vs-individual choice changes recipient UX/notifications/retry -> TC-250-00/02/09.
- Captions or ordering can be silently lost -> tied multi-parent fixtures in TC-250-02/09.
- Large batches can exhaust memory/storage/network -> TC-250-03 preflights bounded metadata before decode/upload.
- Cross-target ciphertext/access reuse leaks content -> TC-250-06/12.
- Partial retry can duplicate successful messages -> TC-250-05/07 stable identity/result grid.
- Authorization/source eligibility may change mid-batch -> TC-250-04/08.
- Lifecycle / derived-state durability: route-local vs durable resume is a ledger decision; TC-250-08 reconstructs only if durability is selected.
- Sibling-surface consistency: plan 237 selection and plan 236 single-output policy are reused, not duplicated -> TC-250-01/04/11.
- Destructive-action side effects: forwarding never mutates/deletes sources or committed outputs; cleanup is batch-owned/uncommitted only -> TC-250-07/08.
- Invariant re-verification under new transitions: every source/target rechecks current integrity, lifecycle, membership, key, and cap at the accepted dispatch boundary.
- Announcement regression -> TC-250-10.

## Acceptance Gates

```bash
# Evidence stop: no batch-forward work while any decision is unresolved
! rg -n '\| unresolved \|' Test-Flight-Improv/250-group-shared-media-batch-forwarding-tdd-plan.md

# Accepted dependencies after plan refresh
test -f Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/237-group-shared-media-library-batch-tdd-plan.md
git status --short
git status --short --untracked-files=all -- go-mknoon/node > /tmp/plan-250-go-node-status.before
git diff --binary -- go-mknoon/node > /tmp/plan-250-go-node-diff.before

# First executable causal RED after TC-250-00; expect non-zero because draft model is absent
flutter test test/features/groups/application/group_media_batch_forward_draft_test.dart --plain-name 'GBF-02 draft output units order and captions match approved contract'

# Focused host GREEN selected by accepted semantics
flutter test test/features/groups/application/group_media_batch_forward_draft_test.dart
flutter test test/features/groups/application/group_media_batch_forward_preflight_test.dart
flutter test test/features/groups/application/group_media_batch_forward_authorization_test.dart
flutter test test/features/groups/application/group_media_batch_forward_provenance_test.dart
flutter test test/features/groups/application/group_media_batch_forward_delivery_test.dart
flutter test test/features/groups/integration/group_media_batch_forward_lifecycle_test.dart
flutter test test/features/groups/presentation/group_shared_media_batch_forward_test.dart
flutter test test/features/groups/presentation/group_media_batch_forward_render_test.dart
flutter test test/features/groups/integration/group_media_batch_forward_transport_boundary_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GBF-06'

# Preserve single-item forwarding, announcements, and transport boundary
flutter test test/features/groups/application/group_media_forward_policy_test.dart
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GMF11|GK030' -count=1)
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# If TC-250-12 is required, refresh with exact path classification and run:
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_batch_forwarding_crypto_proof_test\.dart\t'
./scripts/run_reliability_simulations.sh group --list | rg 'group_batch_forwarding_crypto_proof_test.dart'
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_batch_forwarding_crypto_proof_test.dart --plain-name 'GBF-12 approved multi-source output survives real encrypted group delivery'

# Hygiene
git status --short --untracked-files=all -- go-mknoon/node | cmp -s - /tmp/plan-250-go-node-status.before
git diff --binary -- go-mknoon/node | cmp -s - /tmp/plan-250-go-node-diff.before
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: `external-fixture-blocked` until output unit/restart decisions are accepted. Minimum likely profile is one device using the real Go bridge and destination crypto; an approved new album protocol or cross-target proof may need more peers.
- Boundary being proven: actual chosen output grouping/order/caption/forward marker survives destination-specific upload and encrypted group delivery; an unauthorized target cannot access reused content because none is reused.
- Live availability check: `flutter devices --machine`; no fixed device id is assumed. A new proof must appear as `group/test` in exact discovery records and group `--list`.
- Required setup: plan-236 v98/bridge implementation, multiple verified source fixtures with different captions/tied timestamps, writable target group keys/membership, and any second target needed by the accepted access proof.
- Closure role: required if this plan makes a new real multi-source output claim. Host fakes prove orchestration but not bridge encryption/rendered media-list delivery.
- `FLUTTER_DEVICE_ID`: sufficient only if the refreshed topology uses one in-process real bridge fixture; otherwise the refresh must name additional ids/relay setup.
- Registration: if dedicated proof is required, add exact `integration_test/group_batch_forwarding_crypto_proof_test.dart` to `classify_path` as `group/test` and the group simulator array. Do not rely on a filename pattern.
- Discovery command: the literal `--records-tsv | rg` and group `--list` checks in Acceptance Gates.
- Closure command: the GBF-12 direct device command in Acceptance Gates after topology acceptance.
- Deferred device work: none for selected claims. If accepted implementation is provably just repeated plan-236 outputs and product accepts dependency closure, refresh may justify TC-250-12 as inherited; do not silently make that choice here.

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-250-00 fails because every ledger row is unresolved; plan 237 must keep batch Forward absent.
- Expected first executable RED after evidence: TC-250-02 fails because `GroupMediaBatchForwardDraft` does not exist.
- Green sentinels: plan-236 single-item forward, plan-237 non-forward batch actions, announcement authorization, and pinned Go extra-delivery tests remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Evidence blocker: any unresolved ledger row keeps implementation stopped; looping single-item Forward is not an acceptable default.
- Environment blocker: unavailable selected device/peer/relay or SQLCipher fixture blocks the corresponding promised boundary and final closure.
- Scope drift: unapproved album wire/message type, origin metadata, new migration, Go node/topic/auth/fanout/retry change, or announcement path requires replanning.

- [ ] Evidence Decision Ledger has accepted owner/date/user copy/proof profile for every row.
- [ ] Refreshed plan names exact draft/result/idempotency/cap/caption semantics and files.
- [ ] Every selected behavior has a named causal test or real-boundary proof.
- [ ] First executable RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Output grouping/order/caption and forwarded provenance are exact and origin-minimizing.
- [ ] Every source-target attachment gets fresh encryption/access and current authorization.
- [ ] Partial results/retry never duplicate successes and clean only uncommitted batch-owned state.
- [ ] Plan-237 other batch actions and plan-236 single-item forwarding remain green.
- [ ] Required device proof, announcement/group/feature gates, pinned Go sentinel, analyzer, and hygiene pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-250-00 is unresolved. After accepted/refreshed semantics: `flutter test test/features/groups/application/group_media_batch_forward_draft_test.dart --plain-name 'GBF-02 draft output units order and captions match approved contract'`.
- Preservation command: `flutter test test/features/groups/application/group_media_forward_policy_test.dart` plus plan-237 `GML-05 batch capabilities fail closed and batch forward stays deferred` until the feature is accepted.
- Harness registration: eventual host files into `GROUP_TESTS`; exact group/test device record and simulator entry only if GBF-12 is required.
- Migration: none reserved. If durable restart is accepted, allocate the freshly verified next free version at evidence refresh with host structural and real-SQLCipher device proof.
- Boundary closure: selected album/individual real encrypted output; currently evidence/external-fixture blocked.
- Unresolved evidence: output unit, ordering, captions, provenance/idempotency, cap, partial retry/cleanup, authorization-race, and restart durability.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-09 | evidence gate | plan only | graph/source audit complete | single-item and generic share primitives exist; multi-source semantics do not | all Evidence Decision Ledger rows unresolved | product/security/engineering decision review |
