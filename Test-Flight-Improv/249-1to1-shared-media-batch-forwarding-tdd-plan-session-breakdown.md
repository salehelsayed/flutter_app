# Plan 249 — 1:1 Shared Media Batch Forwarding Session Breakdown

Status: accepted/closed

## Decomposition Progress

| Time | Role / phase | Evidence or decision | Next action |
|---|---|---|---|
| 2026-07-11 | Evidence Collector | An anchored Graphify TDD query and current source confirmed that direct Shared Media already owns a ten-item identity selection and stable SQL keyset order; Plan 232 already owns an ordinary one-source Forward, opaque action token, per-target reminting, encrypted-inner marker, and durable retry; the current picker remains single-caption and permits groups. | Map the settled D-249 authority to an exact closure boundary and Plan-234 integration prerequisite. |
| 2026-07-11 | Closure Mapper | D-249-01..07 resolve to composition over ordinary Plan-232 sends: one output per selected attachment, independent captions/tokens, direct contacts only, atomic all-source eligibility preflight, and a source-by-target result matrix. No new wire, schema, Go, relay, group, or announcement contract is required. | Split source qualification from delivery/picker state and retain independent closure. |
| 2026-07-11 | Session Splitter | Three sessions are sufficient: source-plan refresh plus atomic draft/preflight; direct-contact delivery, preview, and failed-cell retry; then acceptance/document synchronization. Plan 234 Session 04 is the sole inter-plan execution prerequisite. | Counterexample-review the boundaries, tests, gates, and retry truth. |
| 2026-07-11 | Reviewer | The split preserves an atomic source gate before any user-visible action lands, gives the source-target result state one owner, and keeps closure independent. The retry contract distinguishes UI-failed cells from queued/persisted rows whose existing retrier owns stable identity. No device, migration, or receiver-compatibility proof is missing. | Arbitrate structural blockers, merges, splits, and accepted differences. |
| 2026-07-11 | Arbiter | No structural blocker remains in the decomposition. Plan 234 Session 04 subsequently landed and closed, satisfying the sole external prerequisite. No sessions merge or split. Host-only ordinary-send composition is the accepted boundary. | Execute one session at a time; Session 01 is accepted and Session 02 is runnable. |
| 2026-07-11 | Session-02 closure | RED-first direct delivery/picker/action implementation; exact preservation; curated `1to1` `1,962/1,962`; host inventory `87`; completeness `1,174/1,174`; clean static/scope checks; independent QA accepted the explicit bounded `fix_passes=3` exception; exactly one post-QA incremental Graphify refresh. | Session 02 is accepted. Session 03 is the sole pending/runnable Plan-249 session; overall Plan 249 remains open. |
| 2026-07-11 | Session-03 final acceptance | Complete 42-file hash/status baseline; nine mutations repeated causal RED/inverse/GREEN; focused and preservation suites green; curated `1,962/1,962`; host `87`; completeness `1,174/1,174`; analyzer exact parity; QA accepted with `fix_passes=0`; no Graphify refresh. | Session 03 and overall Plan 249 are accepted/closed; index, closure reference, and gate definitions are synchronized. |

## Recommended Plan Count

Create **3** doc-scoped session plans.

## Decomposition Artifact

- Artifact: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md`
- Source: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`
- Detailed planning happens one session at a time.
- Every later session must be refreshed against landed code, especially Plan 234 Session 04, before execution.
- Intended plans:
  - `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-01-plan.md`
  - `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-02-plan.md`
  - `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-03-plan.md`

## Run Mode Snapshot

- Active mode: `implementation-committed gap-closure`.
- Source status vocabulary: the source plan's older `evidence-gated` statements are stale once its D-249 ledger is refreshed from the resolved contract below; the feature remains open until all three sessions are accepted.
- Final verdict policy: `accepted` only after all D-249 decisions are persisted, the user-visible batch flow is implemented, focused and curated gates pass, and the closure/index docs are synchronized. Otherwise the verdict is `still_open` with an exact owned blocker.
- Production edits are forbidden during this decomposition. Downstream execution may edit only the owning session scope.
- Full `host-all` is not a Plan-249/session gate. It remains a later Wave-1/final-rollout obligation.

## Overall Closure Bar

Plan 249 is closed only when a direct Shared Media user can select **1 to 10** eligible received image/video attachments and forward them to one or more eligible direct contacts as **one ordinary outgoing message per selected attachment per contact**, in the exact stable Shared Media keyset order. Every item starts with its own source caption, can be edited or cleared independently, and retains its own opaque Plan-232 operation token across fan-out and failed-only in-route retry. All sources and contacts are re-read before dispatch; one ineligible source aborts the whole source preflight with zero sends. Delivery exposes truthful `sent`, `queued`, and `failed` cells by source and contact, never resends a settled cell, and leaves persisted/queued rows to the existing same-identity direct retry machinery. Private, protected, unsupported, consumed, expired, pending, corrupt, evicted, missing, unresolved, group-owned, deleted-parent, outgoing-source, or otherwise unavailable media fails closed. Existing one-source Forward and all Plan-233 library actions remain unchanged.

Closure is explicitly **host-side composition over the existing ordinary direct send**. It adds no album, shared caption, batch envelope, multi-source payload, receiver behavior, DB migration, Go/libp2p command, relay behavior, group destination, or announcement destination.

## Source Of Truth

The decomposition is governed by:

- User-authoritative Wave-1 D-249 decisions persisted below.
- Source obligations: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`.
- Accepted ordinary Forward: `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md`.
- Accepted direct Shared Media and ten-item selection: `Test-Flight-Improv/233-1to1-shared-media-library-batch-tdd-plan.md`.
- Private-media integration authority: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md`, especially Session 04.
- Stable closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Regression cadence: `Test-Flight-Improv/14-regression-test-strategy.md`.
- Named-gate and target-availability truth: `Test-Flight-Improv/test-gate-definitions.md`; executable arrays in `scripts/run_test_gates.sh` and `scripts/run_host_test_gates.sh` win on disagreement.
- Program index: `Test-Flight-Improv/00-INDEX.md`.
- Direct selection/cursor truth: `lib/features/conversation/application/direct_media_library_controller.dart:8-14`, `:35-91`, `:93-164`; `lib/core/database/helpers/media_library_db_helpers.dart:46-60`, `:102-150`.
- Library action boundary: `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart:35-81`, `:290-374`, `:637-642`; production injection at `lib/features/conversation/presentation/screens/conversation_wired.dart:4427-4495`.
- Existing one-source draft: `lib/features/conversation/application/build_received_media_forward.dart:13-125`.
- Existing opaque intent: `lib/core/services/share_intent_model.dart:8-63`.
- Existing ordinary fan-out/result/persistence behavior: `lib/features/share/application/share_batch_delivery_coordinator.dart:72-180`, `:271-361`, `:604-714`.
- Existing single-caption/target retry UI: `lib/features/share/presentation/screens/share_target_picker_wired.dart:43-140`, `:313-449`, `:465-509`, `:602-627`.
- Direct proof baselines: `test/features/conversation/application/build_received_media_forward_test.dart`, `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`, `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, and `test/features/share/presentation/share_target_picker_wired_test.dart`.

## Resolved Decision Ledger

These decisions supersede the source plan's unresolved D-249-01..07 text. Session 01 must copy them into the source plan before any causal RED or production edit.

| Decision | Accepted contract | Consequence |
|---|---|---|
| D-249-01 output shape | Emit one independent ordinary Plan-232 forward for every selected attachment and every chosen direct contact. Never coalesce attachments that share a parent; never create an album, grouped message, or batch receiver payload. | Three selected attachments to two contacts produce six ordinary outgoing messages in source-major stable order. Receiver compatibility is unchanged. |
| D-249-02 order and captions | Order selected sources by the library's stable keyset `(parent timestamp DESC, message id DESC, attachment id DESC)`, not tap order or file path. Each attachment receives its parent caption as an independent initial value; the user can preserve, edit, or clear each value without affecting siblings. There is no shared caption. | Two attachments from one parent remain two ordered items with two independent caption controllers, even when their initial text is equal. Source rows/text are never mutated. |
| D-249-03 provenance and compatibility | Mint one opaque random Plan-232 `ForwardProvenance.operationDedupKey` per selected attachment when the draft is created. Reuse that item's token across its contact fan-out and failed-only in-route retry. Every destination still receives fresh message/blob IDs, timestamp, recipient key/nonce, and ciphertext through the ordinary send. | No source message/sender/conversation/attachment identity enters wire provenance, outer envelopes, UI, or diagnostics. No new encrypted-inner field or legacy fallback is needed. |
| D-249-04 cap and source eligibility | Selection is `1..10`. Re-read exact direct parent/attachment rows and local bytes immediately before dispatch. Only incoming, live-parent, ordinary, locally complete, integrity-verified, visual Plan-232 sources pass. If any selected source is ineligible, abort the whole source preflight before the first delivery call and keep the selection. | Pending, failed, corrupt, evicted, missing, deleted, outgoing, unresolved/group-owned, private/protected/unsupported/consumed/expired, or stale-path rows cannot produce a partial send. Runtime transport failures after a successful preflight remain truthful per-cell outcomes. |
| D-249-05 result, progress, and retry | Expose a source-by-contact matrix with `sent`, `queued`, and `failed`. Retry only `failed` cells and preserve each source's operation token. Never resubmit `sent` or `queued` cells. A queued/persisted ordinary message is retried by the existing direct retry machinery with its stored message/envelope/attachment identity; it is not a picker failure. | No new batch retry table exists. Pre-message upload failures may be retried only while the action remains open with the same item token; closing and reopening is a new explicit action. Existing persisted direct rows retain restart/reopen recovery. |
| D-249-06 destinations | Plan 249 targets active direct contacts only. Do not load, render, or dispatch groups or announcements. Plans 250 and 251 own those batch-forward lanes. Revalidate every selected contact before dispatch; an invalid contact yields failed cells without changing valid contacts' ordinary-send contract. | No group marker/publish/authorization branch, announcement publisher rule, mixed-destination copy, or lane migration belongs here. |
| D-249-07 UX, privacy, and diagnostics | Show a bounded source preview, item count, independent captions, direct-contact selection, progress, batch-level source denial, and cell outcomes with localized accessible small-screen/RTL behavior. Diagnostics contain only redacted counts, phases, and outcomes. | Do not show provenance, source sender/conversation identity, paths, keys, media bytes, or caption history. No mid-send cancellation promise is added; existing wake-lock/leave protection remains. |

## No-Migration And No-New-Wire Contract

- Plan 249 reserves **no database version** and changes neither production create/upgrade registries nor `currentIdentityDatabaseVersion`.
- It adds no batch-state table, message column, attachment column, album field, provenance array, receiver codec branch, or transport envelope field.
- Every output is an existing ordinary Plan-232 `ShareIntent`/direct send. Per-item in-route retry state is in memory; once an ordinary row is persisted, existing message/attachment tables and retry use cases are authoritative.
- It edits no `go-mknoon`, `go-relay-server`, native platform transport, group publish, or announcement payload file.
- If downstream grounding discovers that any accepted behavior cannot be delivered without schema or wire work, that is a structural contradiction: stop and re-plan. Do not silently widen Plan 249.

## Plan 234 Integration And Ordering Contract

- Plan 249 does not invent or copy a private-media boolean matrix.
- Session 01 was planned while Plan 234 ran, and its production execution waited for accepted Plan-234 Session 04. That prerequisite is now satisfied by `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-04-plan.md`.
- The batch builder/preflight must consume the landed central current-row capability/Forward eligibility decision. A Plan-234 private, unsupported, consumed, expired, or otherwise terminal row receives zero picker/delivery calls.
- Plan 249 adds no migration and therefore does not contend with Plan 234 v100 or Plan 238 v101.
- Session 02 and later Plan-249 work must refresh exact symbols/tests against the already-landed Plan-234 Session-04 qualifier; placeholder file names in this decomposition are not permission to create a second eligibility engine.

## Session Ledger

| Session | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| 01 | Source-plan decision refresh and atomic direct-source draft/preflight | implementation-ready | `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-01-plan.md` | Plan 234 Session 04 | accepted |
| 02 | Direct-contact cell delivery, batch picker UX, and failed-cell retry | implementation-ready | `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-02-plan.md` | Session 01 | accepted |
| 03 | Independent acceptance, gate registration, and closure synchronization | acceptance-only | `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-03-plan.md` | Sessions 01-02 | accepted |

## Ordered Session Breakdown

### Session 01 — Source-plan decision refresh and atomic direct-source draft/preflight

- Session ID: `01`
- Classification: `implementation-ready` with an external prerequisite
- Intended plan: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-01-plan.md`
- Exact scope:
  - Refresh the Plan-249 source header, Problem/Evidence, Scope Guard, Test Contract, device profile, done criteria, and handoff so D-249-01..07 match this accepted ledger.
  - Define one immutable batch draft with `1..10` independently captioned item drafts. Each item carries only its selected `(messageId, attachmentId)`, resolved local visual path, stable library order key, and its own opaque Plan-232 operation token.
  - Build the draft from scoped selected identities by reloading direct parent and attachment rows, applying the landed Plan-234 central Forward capability, checking local path/bytes/integrity/current state, and sorting by the canonical library keyset.
  - Preserve one item per attachment even when parents repeat; initialize captions independently from current parent text; never mutate the source.
  - Add a dispatch-time revalidation API that preserves edited captions and item tokens while re-reading all sources. Return one typed batch-level denial and zero dispatch opportunity if any source fails.
  - Keep the Batch Forward action hidden/unwired in production until Session 02 supplies the complete route and result state.
- Why this is its own session: source qualification is the privacy/correctness boundary. It must become a pure, causally tested foundation before any user-visible multi-send route can call transport.
- Likely production entry files:
  - `lib/features/conversation/application/build_received_media_forward.dart` only to reuse/extract the landed common qualifier, not to change one-source behavior
  - a doc-scoped new application model/builder such as `lib/features/conversation/application/build_direct_media_library_batch_forward.dart`
  - `lib/features/conversation/application/direct_media_library_controller.dart` only if it must expose selected scoped identities/order data without adding transport
  - existing message/media repository interfaces; no new persistence interface
- Likely direct tests/regressions:
  - `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart`
  - Plan-234 central action eligibility test after its exact landed name is refreshed
  - `test/features/conversation/application/build_received_media_forward_test.dart`
  - `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart` as an action-absent/unwired sentinel until Session 02
  - cases for reverse tap order, same-parent siblings, ten/eleven cap, edited/empty independent captions, stable tokens, current-row replacement, private/terminal/unavailable rows, same-ID group/unresolved collisions, and atomic zero-dispatch denial
- Likely named gates:
  - focused new builder/qualifier tests
  - exact Plan-232 and Plan-234 preservation sentinels
  - `./scripts/run_test_gates.sh 1to1`
  - no `core-host-all`, `feature-host-all`, full `host-all`, device, SQLCipher, Go, or relay gate
- Matrix/closure docs: refresh the source Plan-249 contract; register the new direct application file in both 1:1 arrays if it is not already captured; do not mark Plan 249 accepted.
- Historical dependency: accepted Plan-234 Session 04 had to land first and is now satisfied. Session 02 must refresh the exact landed central capability symbols before writing RED.

### Session 02 — Direct-contact cell delivery, batch picker UX, and failed-cell retry

- Session ID: `02`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-02-plan.md`
- Exact scope:
  - Add an application coordinator that first calls Session 01's all-source revalidation, then revalidates selected active direct contacts, and only then composes existing ordinary Plan-232 deliveries.
  - Dispatch source-major in canonical order. For each source, call the existing ordinary coordinator once with that source's `ShareIntent` and its currently valid direct-contact target set so preprocessing is shared per source and encryption/identity remains fresh per target.
  - Map ordinary target results into a source-by-contact matrix. Isolate runtime failures by cell; retain only failed cells for the next send action; remove sent/queued cells from UI retry.
  - Preserve each item's operation token and edited caption across failed-cell retry. Treat queued/persisted rows as durable-retry-owned and expose them truthfully; do not re-dispatch them from the picker.
  - Add a dedicated direct-only picker/preview or a strictly isolated batch mode. It must never load/render groups, must use bounded builder/sliver UI, and must show independent item captions, count/progress, batch-level source denial, and cell summaries in English/German/Arabic with semantics and small-screen/RTL safety.
  - Add the injected Batch Forward action to `DirectSharedMediaLibraryScreen`; keep that screen/controller transport-free. Wire the real route/coordinator from `ConversationWired`, beside the existing injected Save/Share/Delete seams.
  - Preserve selection on preflight denial/cancel; on successful completion, clear sources whose cells are all sent/queued. Keep only sources with failed cells selected if the route returns before those failures are retried.
  - Add redacted diagnostics and use existing upload wake-lock/progress semantics without promising mid-send cancellation.
- Why this is its own session: the result matrix, contact revalidation, delivery sequencing, retry selection, preview, and route wiring form one user-visible state machine. Splitting them would either expose a nonfunctional action or make retry truth depend on two simultaneous implementations.
- Likely production entry files:
  - a new `lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart`
  - a new direct batch picker screen/wired widget and route under `lib/features/share/presentation/`
  - `lib/features/share/application/share_batch_delivery_coordinator.dart` only for the smallest reusable ordinary-result/progress seam, never a multi-source wire model
  - `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`, and generated localization output
- Likely direct tests/regressions:
  - `test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart`
  - `test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart`
  - `test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart`
  - existing `share_batch_delivery_coordinator_test.dart`, `share_target_picker_wired_test.dart`, `conversation_shared_media_library_test.dart`, `direct_media_library_boundary_test.dart`, `build_received_media_forward_test.dart`, and `forwarded_media_retry_roundtrip_test.dart`
  - cases for two sources/two contacts, same-parent sources, target invalidation, source invalidation after preview, sent/queued/failed matrix, failed-cell-only retry, token/caption stability, no group targets, no success replay, source-order mutation, exception isolation, accessibility/l10n, and no provenance diagnostics
- Likely named gates:
  - focused new application/widget/boundary tests and exact Plan-232/233/234 preservation files
  - `flutter test test/l10n/l10n_integrity_test.dart`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_host_test_gates.sh 1to1 --list` to prove registration selection without a second broad execution
  - no feature/core/full host family, device, SQLCipher, Go, or relay gate
- Matrix/closure docs: register every new direct/cross-feature proof file in both 1:1 arrays and classify it in `test-gate-definitions.md`; update the source Test Contract and execution evidence, but leave final acceptance to Session 03.
- Dependency: Session 01.

### Session 03 — Independent acceptance, gate registration, and closure synchronization

- Session ID: `03`
- Classification: `acceptance-only`
- Intended plan: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-03-plan.md`
- Exact scope:
  - Independently audit D-249-01..07 against landed code and prove there is exactly one message per attachment/contact, stable keyset order, independent captions/tokens, atomic source preflight, direct-only targets, and truthful cell retry.
  - Verify Plan-234 private/terminal bypass protection, Plan-232 one-source Forward, Plan-233 Save/Share/Delete/Bookmark/Go-to-message, ordinary direct retry identity, and external-share behavior remain intact.
  - Run representative mutations for source-order reversal, same-parent coalescing, shared-caption collapse, token remint, private eligibility bypass, preflight-after-first-send, group destination exposure, queued/success replay, and source-target matrix flattening; restore each mutation and rerun its exact green test.
  - Prove no migration/version/registry, payload codec, Go/relay, group publish, announcement, or native platform file changed for Plan 249.
  - Run focused suites, the complete curated `1to1` gate, registration/completeness checks, targeted analyzer comparison, `git diff --check`, and baseline-safe scope comparison.
  - Update the source status/checklist/final verdict, this ledger, `00-INDEX`, `19-1to1-message-reliability-closure-reference.md`, and `test-gate-definitions.md`/gate arrays with exact evidence.
- Why this is its own session: it validates two earlier seams together and owns the durable closure record. It must stay independent of implementation and cannot be hidden inside the final picker change.
- Likely direct tests/evidence:
  - all Session-01/02 new files
  - existing Plan-232/233 preservation suites named above
  - Plan-234 central capability test
  - `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`
  - `test/l10n/l10n_integrity_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_host_test_gates.sh 1to1 --list`
  - `./scripts/run_test_gates.sh completeness-check`
  - `flutter analyze` with before/after issue comparison if the repository baseline is nonzero
  - `git diff --check`
  - no full `host-all`; Wave-1 owns the aggregate host gate after all Wave-1 tracks finish
- Matrix/closure docs: this session exclusively assigns the accepted verdict and synchronizes the source plan, breakdown, index, stable 1:1 closure reference, and gate definitions.
- Dependencies: Sessions 01 and 02.

## Why This Is Not Fewer Sessions

Two sessions would force either source qualification and cross-feature transport/UI into one high-blast implementation or erase independent closure. The atomic source gate must land and be proven before a user-visible route can dispatch; the delivery matrix then spans share application state, picker UI, conversation wiring, l10n, and ordinary retry ownership. Independent acceptance must verify both together and synchronize stable docs. Three is the minimum safe set.

## Why This Is Not More Sessions

- Output shape, captions, operation tokens, and source revalidation share one immutable draft/preflight seam and one direct regression family; separating them would be bookkeeping.
- Delivery composition, target revalidation, cell results, failed-only retry, preview, and action wiring are one state machine. Landing only half would expose a misleading or untestable feature.
- There is no separate persistence, migration, wire, receiver, Go/relay, device, group, or announcement slice.
- L10n/accessibility and action-bar wiring belong to the user-visible Session 02 rather than standalone sessions.

## Regression And Gate Contract

- Apply `Test-Flight-Improv/14-regression-test-strategy.md`: causal RED first for every owned behavior, exact preservation sentinels for Plans 232/233/234, and no generic smoke test that merely repeats existing send coverage.
- `Test-Flight-Improv/test-gate-definitions.md` and the two executable 1:1 arrays govern registration. Add each new direct/cross-feature file to both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; verify selection with the host `--list` command.
- Each implementation session runs its focused causal tests and the affected curated `1to1` lane after GREEN. Session 03 reruns the complete Plan-249 focused set and curated lane.
- Do not run `core-host-all`, `feature-host-all`, performance family, or full `host-all` for this host-only composition unless a landed diff materially expands beyond this contract. Full `host-all` runs at Wave-1 and final rollout closure.
- Shared tests outside feature globs run by exact command and remain registered for the later aggregate host sweep.
- Device/relay proof: **N/A**. The receiver and transport see only ordinary Plan-232 messages and no production wire shape changes. If a new wire field appears, the no-new-wire contract is violated and execution stops for re-planning.

## Matrix Update Contract

No new matrix document is needed.

- Session 01 refreshes `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md` so its Test Contract and D-249 ledger are executable.
- Session 02 updates exact gate registration/classification evidence but does not assign final acceptance.
- Session 03 records final evidence and verdict in the source plan and this breakdown; updates `Test-Flight-Improv/00-INDEX.md`; appends the accepted maintenance boundary to `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`; and synchronizes `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and `scripts/run_host_test_gates.sh`.
- Plans 250/251 remain the separate group/announcement batch-forward owners and are not modified or marked covered by Plan 249.

## Downstream Execution Path

For each session, in order:

1. Create or refresh its doc-scoped plan with `$implementation-plan-orchestrator`.
2. Execute and independently QA that plan with `$implementation-execution-qa-orchestrator`.
3. Close its durable docs and ledger row with `$implementation-closure-audit-orchestrator`.
4. Refresh the next session against landed code before planning it.

Session 01 honored its prerequisite and is accepted. Every later session must
reuse and refresh against the landed Plan-234 Session-04 qualifier rather than
bypassing it with a local private-media check.

## Reviewer Answers

- Recommended count: sufficient and minimal; neither too coarse nor fragmented.
- Sessions to merge: none.
- Sessions to split: none.
- Missing tests/gates: none after adding the atomic preflight, canonical order, per-item caption/token, direct-only destination, cell retry, Plan-234 bypass, transport-boundary, l10n, registration, mutation, and curated `1to1` proofs above.
- Meaningful endpoints: Session 01 leaves a complete hidden pure draft/preflight foundation; Session 02 leaves the complete user-visible host feature; Session 03 leaves an independently accepted maintenance record.
- Matrix responsibility: explicit; Session 03 owns final synchronization.
- Minimum safe session set: three.

## Arbiter Verdict

- Structural blockers: none in the decomposition.
- Execution prerequisite: satisfied; Plan 234 Session 04 is accepted and closed.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences: host-only ordinary-send composition; no album/shared caption; no group/announcement targets; no batch-draft restart persistence; no new DB/wire/device/relay proof; no private-media forwarding.

## Structural Blockers Remaining

None. Plan 234 Session 04 and all three Plan-249 sessions are accepted and
closed. Sessions 01-02 each retain their sole post-QA code refresh; acceptance-
only Session 03 ran no Graphify refresh. Overall Plan 249 is accepted/closed.

## Accepted Differences Intentionally Left Unchanged

- Plan-232 current-item/message Forward remains a separate one-source flow.
- Plan-233 Save, external Share, Delete, Bookmark, viewer, and Go to Message remain independent.
- Groups and announcements remain Plans 250/251.
- A failed pre-message upload has no durable message identity; it may reuse the same per-item operation token only while the picker stays open. Once a message row exists, existing persisted retry is authoritative. Closing and reopening an unpersisted action is a new explicit Forward.
- Receiver UI continues to show ordinary forwarded messages; there is no album or batch indicator.
- Device/relay evidence is intentionally N/A because no boundary changes.

## Exact Docs And Files Used As Evidence

- `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`
- `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md`
- `Test-Flight-Improv/233-1to1-shared-media-library-batch-tdd-plan.md`
- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`
- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/features/conversation/application/direct_media_library_controller.dart`
- `lib/features/conversation/application/build_received_media_forward.dart`
- `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/core/database/helpers/media_library_db_helpers.dart`
- `lib/core/services/share_intent_model.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`
- Direct Plan-232/233 tests named in `Source Of Truth` and the ordered sessions.

## Why This Decomposition Is Safe For Downstream Planning And Execution

The artifact turns every formerly open D-249 choice into a concrete, testable contract; isolates the privacy-sensitive source gate before transport; reuses the accepted ordinary send/retry path instead of inventing a protocol; assigns one owner to the source-target result state; names exact preservation and gate obligations; records the only inter-plan prerequisite; and leaves independent acceptance plus durable documentation ownership. A downstream planner can therefore write causal REDs without guessing output, caption, provenance, destination, persistence, or device semantics.
