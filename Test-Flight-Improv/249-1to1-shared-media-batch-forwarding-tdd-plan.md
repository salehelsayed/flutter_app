# 249 - 1:1 Shared Media Batch Forwarding

Status: evidence-gated
Type: New Feature
Spec: free-text intent — forward a bounded multi-message selection from the direct Shared Media library without collapsing captions, ordering, provenance, dedup, encryption, or partial retry truth
Classification: evidence-gated
Closure tier: host/paired-device conditional

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; plans 232/233; `ShareIntent`; share picker/screen/wired/coordinator and tests; direct `dedupKey` send/receive/retry tests; group destination branch | Plan 232 deliberately has one source message/current item, one caption, and one opaque provenance key. Plan 233 can select entries from several parent messages. Flattening that selection into the current intent would invent album, caption, and receiver-dedup behavior. | Resolve D-249-01..07, refresh the output/provenance/retry contract, then author REDs or split a new-wire branch before implementation. |
| 2026-07-10 | Dependency refresh | revised plan 228 owner-scoped library/cursor contract and shared migration registry | Any future batch selection must contain resolved `direct` entries from one scope/filter-bound cursor sequence; local owner identity is dispatch-only and never provenance. Conditional schema must extend the shared registry. | Preserve the evidence gate and add these invariants to the post-decision refresh. |

## Problem And Evidence

- Behavior to improve: a user selecting several images/videos in one direct Shared Media library should be able to forward them to one or more eligible contacts/groups with predictable grouping, order, captions, markers, privacy, and retry results.
- Impact: a naive implementation can collapse unrelated source messages under one dedup key, lose captions, reorder items, reuse encryption material, duplicate successful deliveries during retry, or leak original sender/conversation identity.
- Confirmed current mechanism: `ShareTargetPickerScreen` accepts one `captionController` and one file-path collection (`lib/features/share/presentation/screens/share_target_picker_screen.dart:19-51`, `:63-70`). It has no per-source caption or album model.
- Confirmed current mechanism: `DefaultShareBatchDeliveryCoordinator.deliver` preprocesses one shared intent then iterates selected targets at `lib/features/share/application/share_batch_delivery_coordinator.dart:163-217`; the contact leg mints/uploads/sends from that single intent at `:279-357` and the group leg follows a separate contract at `:382-485`.
- Confirmed direct contract: plan 232 intentionally builds provenance from one source message (`source.dedupKey ?? source.id`), gives each target fresh identity/encryption, and stores one forwarded marker. Its scope explicitly excludes a multi-message library selection.
- Confirmed library contract: plan 233 pages/selects stable `MediaLibraryEntry` values across parent messages and owns batch Save/Share/Delete, but deliberately exposes no batch Forward action.
- Existing coverage: single-source forward draft/picker/fan-out/dedup/retry tests in plan 232; library selection/filter/paging tests in plan 233; existing picker tests for target-set uniqueness and failed-only target retry. None can distinguish multiple source keys/captions within one selection.
- Missing coverage: album-versus-individual output, stable selection/order cap, caption ownership, duplicate source-parent coalescing, per-source/per-target provenance, receiver dedup, encryption/ID fan-out, partial result matrix, retry/reopen, legacy fallback, group destination semantics, and wire/transport boundary.
- Refuted finding: one `ForwardProvenance.dedupKey` cannot truthfully represent attachments from several source messages. Reusing it can make receiver dedup collapse unrelated forwarded content; dropping it loses the source-replay guarantee.
- Refuted finding: concatenating captions or silently choosing the first caption is not a source-grounded product rule.
- Unresolved findings (blocking): **D-249-01** send one album/grouped message versus one forwarded message per source parent/attachment, including duplicate attachments from the same parent; **D-249-02** stable order, caption preservation/edit/removal, per-item versus shared caption, and receiver presentation; **D-249-03** per-source/per-target opaque provenance shape, dedup discriminator, legacy fallback, and whether a new encrypted-inner wire field is required; **D-249-04** selection/media/byte cap, mixed unavailable/protected state, preprocessing/memory limits, and all-or-eligible-subset behavior; **D-249-05** per-source/per-target result, cancellation, queued state, failed-only retry, restart, idempotency, and whether successes remain selected; **D-249-06** group destinations, plan-236 marker/dedup interaction, announcements, permission revalidation, and mixed direct/group result copy; **D-249-07** confirmation/preview, privacy disclosure, diagnostics, accessibility, and whether multi-source forwarding is available before every recipient supports the chosen contract.
- Affected production/test/gate files are conditional: a library Forward action; a multi-source draft/preview; picker/coordinator extensions; possibly direct inner payload/retry state and a freshly allocated DB vNEXT; three-locale l10n; focused host tests; and a paired-device proof only if decisions introduce a new wire shape. Exact files cannot be frozen before D-249-01..07.

## Scope Contract And Guard

Conditionally in scope after D-249-01..07:
- Add Batch Forward to plan 233 only for a non-empty, bounded, eligible selection and preserve stable attachment/message identity from selection through result handling.
- Implement exactly one approved output model: ordered individual forwards or an explicitly defined album/group. Specify how selected attachments sharing a parent message coalesce and how captions are preserved/edited/removed.
- Carry an approved opaque provenance value for every logical source through every destination. Each destination still gets fresh message/blob IDs, timestamps, recipient-scoped keys/nonces, and independent retry identity.
- Extend picker preview/result state to the approved per-source/per-target matrix; revalidate contact/group eligibility immediately before each send and retain exactly the approved failed/cancelled cells for retry.
- Keep provenance and forwarding markers encrypted-inner-only and attribution-free. Diagnostics may use redacted stable prefixes/outcome counts, never source keys, sender identity, captions, paths, or media bytes.
- If durable grouped retry state needs schema, allocate DB vNEXT only after approval and a fresh version-ledger conflict check; reserve no number here.

Must preserve:
- Accepted Plan 232 one-source viewer/bubble Forward remains unchanged -> TC-249-01/12.
- Plan-233 paging, filters, bookmarks, Save/Share/Delete, selection, and Go to Message remain usable with Batch Forward unavailable/disabled -> TC-249-01/10/12.
- Every target gets new recipient-scoped upload encryption and no source file/key/row/caption is mutated -> TC-249-05/09.
- Existing writable-group checks, group encryption/publish/background-task lifecycle, and plan-236 marker rules remain owning behavior -> TC-249-07/11.

Hard `Do not`:
- Do not expose Batch Forward, invent album semantics, concatenate/select captions silently, or flatten several source keys until D-249-01..07 are approved and this plan is refreshed.
- Do not reuse one source dedup key for unrelated parent messages, expose original sender/conversation identity, or put provenance in a v2 outer envelope/diagnostic.
- Do not reuse message/blob IDs, encryption keys/nonces, ciphertext, or queued identity across targets.
- Do not send pending, missing, evicted, integrity-failed, expired, or protected media contrary to the approved D-249-04 policy.
- Do not edit go-libp2p, relay framing/routing, group publish/auth internals, or announcement payloads in this plan.
- Do not reserve a migration version speculatively. The landed spine is plan 228 `v96` shared media state, plan 232 `v97` direct forwarded marker, plan 235 `v98` group deletion journal, and plan 236 `v99` group forwarded marker; later work may advance the ledger before this plan is approved.
- Do not accept plan-228 `unresolved` or group-owned source entries in a direct batch, reuse a cursor after scope/filter change, or serialize local owner identity into wire provenance/diagnostics.

Deferred / accepted difference:
- Plan 233 ships batch Save/Share/Bookmark/Delete/Go to Message without Batch Forward; the missing action is intentional until this plan becomes execution-ready.
- Single source-message/current-viewer-item Forward remains plan 232 and does not wait for this plan.
- Announcement-source/destination forwarding policy remains plan 240; this plan cannot infer announcement permissions.
- If D-249-01/03 selects an album/new wire contract rather than ordinary individual sends, refresh or split that wire slice for independent `$tdd-review` and paired-device closure.

Dependencies:
- Plan 228 supplies resolved owner-scoped library entries, scope/filter-bound cursors, the `1..100` query ceiling and shared production migration registry.
- Accepted `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` supplies one-source `ForwardProvenance`, picker launch, direct forwarded marker, fresh per-target encryption, dedup, and retry primitives.
- Accepted `Test-Flight-Improv/233-1to1-shared-media-library-batch-tdd-plan.md` supplies stable bounded selection and library UI without Batch Forward.
- Implemented/device-proven `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` supplies the group DB `v99` marker/dedup behavior required before group destinations can claim parity.
- Accepted `Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md` supplies announcement policy.
- D-249-01..07 are approval dependencies; any new schema/wire shape is allocated and reviewed only after decisions.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-249-01 | Plan 233 exposes no Batch Forward action while the contract/configuration is undecided, and all existing library actions plus plan-232 single-source Forward remain available. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::batch forward stays absent until multi-source policy is approved` | future `GREEN sentinel` / plan-233 library + plan-232 action fixtures | HEAD/library plans lack Batch Forward -> after dependencies the exact absence/core-action assertions stay GREEN until approved configuration exists | enable on missing policy, hide Save/Share/Delete, or suppress single-source Forward -> TC-249-01 red | Reserve this named test in plan-233 file/both 1:1 arrays when dependencies execute; no production action before D-249 approval |
| TC-249-02 | Selection uses stable attachment/message IDs from one direct scope/filter signature, applies the approved cap, preserves repository order, and rejects group/unresolved/cursor-mismatched entries. | `test/features/conversation/application/build_shared_media_batch_forward_test.dart::selection enforces direct ownership cursor signature cap order and parent grouping` | evidence-gated host application / mixed direct/group/unresolved pages, stale cursor and file sizes | HEAD compile RED: builder absent -> exact selected IDs/order/ineligible result follow D-249-01/04 and no cross-owner entry reaches preprocessing | key by path, exceed cap, reuse stale cursor, reorder, or include group/unresolved/protected media -> TC-249-02 red | `flutter test test/features/conversation/application/build_shared_media_batch_forward_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-249-01/04 |
| TC-249-03 | The approved album-versus-individual output creates the exact logical message count/order and assigns captions according to the approved per-source/shared edit model. | `test/features/conversation/application/build_shared_media_batch_forward_test.dart::approved output shape preserves order and caption ownership` | evidence-gated host application / three attachments across two captioned parent messages | HEAD causal gap: no output contract -> exact message/album/caption mapping becomes observable after D-249-01/02 | collapse two parents, concatenate/choose first caption, reorder items, or apply one edit to the wrong source -> TC-249-03 red | Same focused file; reserve both 1:1 arrays; blocked by D-249-01/02 |
| TC-249-04 | Every logical source carries only its approved opaque provenance through encrypted inner state; outer payload/UI/diagnostics reveal no source key, sender, contact, conversation, or caption history. | `test/features/conversation/domain/models/multi_source_forward_provenance_test.dart::per-source provenance is opaque inner-only attribution-free and legacy-safe` | evidence-gated domain host / v1/v2/legacy codec matrix + event sink | HEAD compile RED: multi-source provenance absent -> exact list/map/fallback and negative fields follow D-249-03/07 | reuse one key, expose array in outer envelope, serialize sender identity, or log provenance -> TC-249-04 red | `flutter test test/features/conversation/domain/models/multi_source_forward_provenance_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-249-03/07 |
| TC-249-05 | For every approved source-target cell, preprocessing is bounded and each destination gets fresh message/blob identity and independently generated key/nonce while source bytes/rows/keys remain unchanged. | `test/features/share/application/multi_source_forward_delivery_coordinator_test.dart::fanout preserves sources and remints identity encryption per source target` | evidence-gated host application / two sources, two contacts, content-transforming bridge, temp snapshots | HEAD compile RED: coordinator shape absent -> exact call matrix and distinct ids/keys/nonces follow D-249-01/04 | reuse an upload/key across targets, mint one ID per batch, preprocess unboundedly, or mutate a source -> TC-249-05 red | `flutter test test/features/share/application/multi_source_forward_delivery_coordinator_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-249-01/04 |
| TC-249-06 | Receiver dedup uses the approved per-source/group discriminator: replay drops only the matching logical source, distinct selected sources survive, and a genuine repeat remains possible as approved. | `test/features/conversation/integration/multi_source_forward_dedup_test.dart::receiver dedups each approved source without collapsing siblings or genuine repeat` | evidence-gated host integration / two-user v2 fake transport + replay controls | HEAD lacks multi-source flow -> exact card/receipt counts depend on D-249-01/03 but must distinguish replay, sibling, and genuine repeat | hash content, use one batch key, omit sender/contact discriminator, or drop a distinct source -> TC-249-06 red | `flutter test test/features/conversation/integration/multi_source_forward_dedup_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-249-01/03 |
| TC-249-07 | Picker preview and multi-target send revalidate namespaced contacts/writable groups once, preserve approved source order/captions, and return a per-source/per-target result matrix. | `test/features/share/presentation/share_target_picker_wired_test.dart::multi-source forward revalidates targets and returns approved result matrix` | evidence-gated widget host / mixed contact/group selections + recording coordinator | HEAD partial: target sets/one-intent results exist but multi-source preview/matrix does not -> exact cells and stale-target removal follow D-249-05/06 | flatten results by target only, skip group revalidation, duplicate namespaced key, or reorder previews -> TC-249-07 red | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'multi-source forward revalidates targets and returns approved result matrix'`; AUTO + both 1:1 arrays; blocked by D-249-05/06 |
| TC-249-08 | Failure/cancel/queue/retry/reopen preserves the approved cells, never resends successes, reuses stored send identity/envelope, and settles truthful partial status. | `test/features/share/integration/multi_source_forward_retry_test.dart::partial matrix retries failed cells only across reopen without reminting` | evidence-gated host integration / gated source-target failures + repository recreation | HEAD compile RED: result/retry matrix absent -> exact retained cells/status/identities follow D-249-05 | clear all selection, retry successes, remint queued identity/key, or report whole batch success -> TC-249-08 red | `flutter test test/features/share/integration/multi_source_forward_retry_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-249-05 |
| TC-249-09 | If approved retry/provenance state needs new schema, a freshly conflict-checked DB vNEXT extends the shared production registry, preserves owner/local-state predecessors and survives PRAGMA/before-after/run-twice/encrypted reopen; otherwise the row records exact N/A. | `test/core/database/migrations/shared_media_batch_forward_state_migration_test.dart::approved vNEXT preserves owner scoped prior rows and batch retry state idempotently` plus `integration_test/shared_media_batch_forward_sqlcipher_proof_test.dart` | conditional host structure + Android/iOS real SQLCipher / same-ID direct/group/unresolved predecessor | HEAD evidence gap: no schema decision/version -> exact columns/defaults/checks/actual registry/full-chain/device proof follow D-249-03/05 and a fresh ledger check | recreate callbacks, omit state/default/guard, reclassify unresolved, lose a sibling, or fail reopen/rerun -> TC-249-09 red if schema selected | Reserve no number; refresh literal host/Android/iOS commands and exact `1to1` discovery only if schema is approved, otherwise document N/A with existing persisted-send tests |
| TC-249-10 | Preview, cap/selection count, caption controls, per-target progress, partial results, and confirmations are localized, accessible, virtualized, and RTL-safe on small screens. | `test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart::multi-source preview is bounded localized accessible and RTL-safe` | evidence-gated widget / en/de/ar, semantics tester, 320x568, large bounded fixture | HEAD causal RED: action/preview absent -> exact approved controls/copy become assertable after D-249-01/02/04/05/07 | build all items eagerly, hardcode English, hide per-cell failures, or lose order semantics -> TC-249-10 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart`; reserve AUTO + both 1:1 arrays + ARB parity; blocked by D-249 decisions |
| TC-249-11 | Group destinations follow plan-236 marker/dedup/permissions exactly; announcements follow plan 240; mixed destinations cannot inherit direct-only provenance or bypass writable policy. | `test/features/share/application/multi_source_forward_destination_boundary_test.dart::batch forward preserves direct group and announcement ownership` | evidence-gated host source/behavior contract / direct+group spies and announcement policy fixture | HEAD has separate group branch but no multi-source rule -> exact allowed/denied matrix follows D-249-06 and dependencies 236/240 | inject direct provenance into group payload, bypass writable group, or enable announcement implicitly -> TC-249-11 red | `flutter test test/features/share/application/multi_source_forward_destination_boundary_test.dart`; reserve AUTO + direct/group owning gates only after D-249-06 |
| TC-249-12 | Plan-232 single-source Forward and plan-233 library Save/Share/Delete/Bookmark/Go-to-message remain unchanged under disabled/cancelled/successful batch flow. | Plan-232 focused tests plus plan-233 focused tests | `GREEN sentinels` / existing host fixtures | GREEN after dependencies -> remain GREEN after approved batch implementation | route a one-source action through ambiguous batch state or clear library selection on unrelated action -> sentinels red | Run plan-232/233 focused suites and both 1:1 gates; exact commands are already literal in those accepted plans |
| TC-249-13 | The chosen implementation changes no Go/libp2p/relay routing; if D-249-01/03 introduces a new encrypted-inner wire shape, two direct peers prove the production send/retry/receive leg end to end. | `test/features/conversation/application/shared_media_batch_forward_transport_boundary_test.dart::batch forwarding is Dart-owned and Go-opaque` plus conditional `integration_test/direct_multi_source_forward_real_harness.dart::approved batch arrives ordered deduped and attribution-free` | host source-contract + conditional paired-device real transport / one pinned USB physical Android plus one available Android emulator by default, fully automated | HEAD compile RED: batch sources absent; paired-device GREEN undefined until output/wire decision -> forbidden Go paths remain unchanged and any approved new wire survives the actual boundary | add Bridge/Go command, expose provenance outer-side, reorder/drop one source, or duplicate on retry -> TC-249-13 red/fails device proof | Reserve host file in both 1:1 arrays; add a dedicated exact `1to1` paired-device record only if refreshed plan changes wire shape; pin discovered target IDs, record unavailable mobile legs N/A, and retain baseline-safe Go/relay diff comparison |

### Test Notes

- TC-249-03/04/06 are the central decision triangle. Output grouping, provenance cardinality, and receiver dedup must be decided together; approving only one leaves the plan evidence-gated.
- TC-249-05 counts distinct IDs/keys/nonces for every logical source-target cell, not merely upload call count.
- TC-249-08 must represent partial success in both dimensions. A target-only `success/failure` list is underpowered when some sources succeed and others fail for the same target.
- TC-249-09 reserves no version. It is removed as N/A if approved individual forwarding reuses existing persisted direct/group rows without new durable batch state.
- TC-249-13 requires paired-device proof only for a genuinely new wire/output contract; ordinary repeated plan-232 sends must not gain ceremonial device scope.

## Implementation Steps

1. Do not implement. Resolve D-249-01..07 with product/messaging/privacy owners, including one worked example with three attachments from two captioned source messages and mixed contact/group targets.
2. Refresh this plan with the exact output count/order, caption mapping, provenance schema/cardinality, selection caps, eligibility behavior, per-source/per-target state machine, legacy fallback, and group/announcement matrix.
3. If decisions introduce a new direct inner wire shape, isolate that slice, name the production end-to-end leg, and run `$tdd-review`; if they require schema, allocate vNEXT only after a fresh conflict check.
4. After an execution-ready verdict, add causal builder/provenance/delivery/dedup/retry REDs before production edits while keeping TC-249-01/12 sentinels GREEN.
5. Implement pure draft/output policy first, then picker preview/result matrix, then delivery/retry persistence, then lane integration/l10n.
6. Run focused host gates, dependency sentinels, representative grouping/provenance/crypto/retry mutations, and only the conditional boundary proof selected by the refreshed contract.

## Risks And Blind Spots

- A single source key can collapse unrelated selections -> TC-249-03/04/06.
- Batch retry can redeliver successes or remint identities -> TC-249-07/08.
- Large selections can cause memory/crypto bursts -> D-249-04 and TC-249-02/05/10 require explicit bounds and virtualization.
- Lifecycle / derived-state durability: TC-249-08 recreates retry state; TC-249-09 supplies SQLCipher reopen only if new schema is selected.
- Sibling-surface consistency: TC-249-01/12 keep single-source Forward and every plan-233 library action intentionally independent.
- Destructive-action side effects: N/A — Batch Forward creates new destination rows and must not mutate/delete source state; TC-249-05/08 assert source and success-cell preservation.
- Invariant re-verification under new transitions: every delayed target result/retry rechecks selected source identity, target writability, stored send identity, and current eligibility in TC-249-07/08.

## Acceptance Gates

```bash
# Snapshot before any future execution; record unrelated changes
git status --short

# Structural blocker inventory only; this does not approve the decisions
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/233-1to1-shared-media-library-batch-tdd-plan.md
rg -n 'D-249-01|D-249-02|D-249-03|D-249-04|D-249-05|D-249-06|D-249-07' Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md

# Approval evidence gate: no shell command can close it. Written D-249-01..07,
# refreshed exact output/provenance/retry contracts, and tdd-review are required.

# First causal RED: N/A while output/caption/provenance semantics are unspecified.

# Preservation baseline after plans 232/233 land
flutter test test/features/conversation/application/build_received_media_forward_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list

# Conditional vNEXT/device commands are inserted only by the refreshed plan;
# placeholders are not executable acceptance gates while evidence-gated.

flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile status: decision-blocked. D-249-01/03 determines whether this is composition over ordinary plan-232 sends or a new grouped/wire contract.
- Ordinary-individual branch: if every approved output is an independent existing plan-232 send with unchanged inner payload, host fan-out/dedup/retry proofs plus plan-232 preservation close the feature; no extra relay/device ceremony is justified.
- New-album/wire branch: require a dedicated paired-device direct scenario over the production transport with actual media upload/encryption/send/retry/receive, proving order, captions, per-source dedup, markers, attribution privacy, and failed-only retry. Add exact accounts/devices/relay setup and runner during refresh.
- Group destination branch: consume plan-236's real boundary evidence for unchanged group sends; add a new group device scenario only if D-249-06 changes the group payload/wire contract.
- SQLCipher branch: only if D-249-05 selects new durable batch state, allocate vNEXT after a fresh ledger check and run dedicated PRAGMA/before-after/reopen/run-twice proof on each applicable Android/iOS target available at execution. Unavailable platform legs are `N/A (target unavailable by project policy)`. No version is reserved now.
- Registration: dedicated exact `1to1` records only; do not broaden-classify mixed SQLCipher or generic messaging suites.
- Go/relay scope: the plan must remain Go-opaque. Any new Go/protocol requirement is a separate plan and blocks this one from reclassification.

## Execution Interpretation And Done Criteria

- Expected RED: N/A while evidence-gated; no honest GREEN exists for album/message count, captions, provenance, or retry matrix until D-249-01..07 are approved.
- Green sentinel: plan-232 single-source Forward and plan-233 library actions remain unchanged with Batch Forward absent.
- Pre-existing dirty tree / known failure: snapshot at any future execution start; preserve unrelated Go test-vector and other user changes with a baseline-safe path comparison rather than raw clean-tree assumptions.
- Environment blocker: none currently determines status. Product/wire decisions are the blocker; paired devices become a blocker only for a selected new-wire branch.
- Scope drift: guessed grouping/captions/provenance, speculative migration, Go/relay edits, or unapproved group/announcement behavior blocks progress.

- [ ] D-249-01..07 form one consistent output/provenance/dedup/retry contract with worked examples.
- [ ] The refreshed plan names exact selection caps, caption mapping, result cells, legacy fallback, and privacy negatives.
- [ ] Every approved behavior has a causal test/mutation and every new test has exact owning gate registration.
- [ ] Any vNEXT is freshly conflict-checked and receives structural/full-chain plus real-SQLCipher proof.
- [ ] Any new wire/output contract has production paired-device proof; ordinary-send composition avoids unnecessary transport edits.
- [ ] Plans 232/233 and group/announcement ownership remain intact.
- [ ] Analyzer, diff hygiene, and baseline-safe Go/relay scope comparison pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: N/A — approve D-249-01..07, refresh the plan, and run `$tdd-review` before authoring behavior tests.
- Preservation command: `flutter test test/features/conversation/application/build_received_media_forward_test.dart test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart`.
- Manual registration: after refresh, add dedicated direct host files to both 1:1 arrays; add dedicated SQLCipher/paired-device discovery only for the selected schema/wire branch.
- Migration: none reserved; allocate vNEXT only if approved retry/provenance durability cannot reuse existing persisted sends, after a fresh conflict check.
- Boundary closure: host-only for composition over ordinary plan-232 sends; paired-device production transport for an approved album/new-wire branch; no Go/relay edits in either case.
- Unresolved evidence: D-249-01..07 and the resulting ordinary-send-versus-new-wire branch. Status remains `evidence-gated`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | D-249-01..07 unresolved | obtain decisions and refresh plan |
