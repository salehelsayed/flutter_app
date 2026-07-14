# Plan 249 Session 01 — Source-plan refresh and atomic direct-source draft/preflight

Status: accepted
Source: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md` Session 01
Run mode: implementation-committed gap-closure
Classification: host-only hidden application foundation
Dependency: Plan 234 Session 04 is accepted and closed; Plans 232 and 233 are accepted

## Planning Progress

| Time | Role / phase | Evidence or decision | Next action |
|---|---|---|---|
| 2026-07-11 | Evidence Collector | Read the complete Plan-249 source and accepted three-session breakdown; verified accepted Plans 232/233 and closed Plan-234 Session 04; inspected current direct selection, keyset SQL, current-row qualification, one-source Forward, Shared Media action boundary, ordinary delivery, picker, tests, and both 1:1 arrays. | Freeze Session 01 to the source-plan refresh and hidden atomic draft/preflight seam. |
| 2026-07-11 | Graphify TDD grounding | Anchored current architecture context (`confidence=anchored`, `freshness=current`, fingerprint `512b7944a27b6b11`) on `qualifyCurrentDirectMediaRow`, `ONE_TO_ONE_TESTS`, and `ONE_TO_ONE_HOST_TESTS`; current source verification confirmed the exact direct parent/attachment qualifier and preservation suites. | Name the causal REDs, exact write scope, and proportional gates. |
| 2026-07-11 | Dependency refresh | Plan-234 Session 04 is accepted/closed and supplies the mandatory exact-current private-media decision. The historical `prerequisite-blocked` Plan-249 ledger state is therefore satisfied. | Execute against the landed central qualifier; do not copy or fork its policy matrix. |
| 2026-07-11 | Session planner | D-249-01..07 are one settled ordinary-send contract: independent attachment drafts, canonical order, independent captions/tokens, atomic all-source preflight, direct contacts only, and no schema/wire/device scope. | Capture a fresh dirty-tree baseline, refresh the stale source contract, then author causal REDs before production. |

## Execution Preflight

- **Session 01 is accepted and closed.** The causal RED, sole production file,
  tests, registrations, literal gates, final Graphify `affected`, fresh
  independent QA, and the one authorized post-QA incremental refresh are
  recorded below. Session 02 is runnable; overall Plan 249 remains open.
- At execution start, run `git status --short` and record a fresh scoped per-file hash/status snapshot before changing the source plan, tests, gate arrays, or production.
- **Scoped execution baseline:** `2cf58536abfdf0db15ece27e655e454cee1e5c02130d618157a043f3e74bb4b6` over the 20 existing source/plan/authority/preservation/gate paths listed below, captured after this plan was materialized and before any source-plan, test, gate, or production edit. The earlier plan-exclusive owner/test/gate aggregate was `10899f0c3499528d68ef6a59d229574278ec3c3fd25816376e8ff5327e93274e`.
- The new production and causal-test paths are expected to be absent before RED. Record their absence explicitly rather than hashing an invented placeholder.
- Baseline at least these existing paths:
  - `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`
  - this Session-01 plan
  - `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md`
  - `lib/features/conversation/application/received_media_action_controller.dart`
  - `lib/features/conversation/application/private_media_action_eligibility.dart`
  - `lib/features/conversation/application/build_received_media_forward.dart`
  - `lib/features/conversation/application/direct_media_library_controller.dart`
  - `lib/features/conversation/domain/models/media_library.dart`
  - `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
  - `lib/core/database/helpers/media_library_db_helpers.dart`
  - `test/features/conversation/application/private_media_action_eligibility_test.dart`
  - `test/features/conversation/application/direct_private_media_boundary_test.dart`
  - `test/features/conversation/application/received_media_action_controller_test.dart`
  - `test/features/conversation/application/build_received_media_forward_test.dart`
  - `test/features/conversation/application/direct_media_library_batch_actions_test.dart`
  - `test/features/conversation/application/direct_media_library_boundary_test.dart`
  - `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart`
  - `scripts/run_test_gates.sh`
  - `scripts/run_host_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
- The worktree is intentionally shared and dirty. Existing Plan-234 Session-04 edits, gate registrations, Graphify artifacts, rollout documents, and unrelated changes are baseline. Never reset, stash, revert, rewrite, or attribute them to Plan 249.
- Capture the forbidden-scope path list from the exact scope-guard command below before RED. The post-implementation list may contain the same pre-existing paths, but Session 01 may add none.
- **Forbidden-scope baseline:** only the pre-existing `app_database_version.dart`, `production_migration_registry.dart`, `conversation_wired.dart`, `direct_shared_media_library_screen.dart`, two group repository files, and seven generated/source l10n files. No Plan-249 production/test file existed when captured.

## Session Objective

Make the accepted Plan-249 contract executable and land only its pure hidden source foundation:

1. Refresh the stale source Plan 249 from `evidence-gated` unresolved/conditional language to the accepted D-249-01..07 ordinary-send contract.
2. Add one immutable direct-library batch-forward draft builder for `1..10` exact selected `(messageId, attachmentId)` identities from one direct contact scope.
3. Qualify every source through the landed Plan-234 exact-current direct-row boundary before returning any draft.
4. Sort qualified sources by the canonical Shared Media keyset, initialize independent captions, and mint one unique opaque Plan-232 operation token per attachment.
5. Add dispatch-time all-source revalidation that preserves each identity's edited/cleared caption and operation token while refreshing current rows, paths, and canonical order.
6. Keep Batch Forward absent and unwired in production until Session 02 supplies the complete direct-contact route, matrix state, and retry UX.

Session 01 closes only the source-plan decision refresh and hidden draft/preflight foundation. It does not make Plan 249 accepted and does not expose a usable feature.

## Accepted Contract Frozen For This Session

### Immutable draft vocabulary

Add `lib/features/conversation/application/build_direct_media_library_batch_forward.dart` with a non-Flutter application API equivalent to:

- `DirectMediaLibraryBatchForwardItemDraft`
  - exact `DirectReceivedMediaActionIdentity`;
  - current resolved local visual path;
  - current parent timestamp used by the canonical ordering key;
  - independent caption string, including an allowed empty value;
  - one non-empty opaque `ForwardProvenance.operationDedupKey` value;
  - immutable copy/update semantics so later UI can edit one caption without mutating siblings.
- `DirectMediaLibraryBatchForwardDraft`
  - an immutable ordered list of `1..10` item drafts;
  - no shared caption, batch provenance token, target state, transport state, or persistence handle.
- A typed build/revalidation result with either one complete ready draft or one non-sensitive batch denial. A denial exposes no partial ready subset, path, caption, token, sender, contact payload, key, nonce, or media bytes.
- `BuildDirectMediaLibraryBatchForward.build(...)` for initial draft creation.
- `BuildDirectMediaLibraryBatchForward.revalidateForDispatch(...)` for the Session-02 dispatch boundary.

Exact public spelling may change only if the causal tests and source-plan refresh use one consistent name. Do not create a second private-media or egress policy type.

### Source identity and scope

- Input is one expected direct `contactPeerId` plus `1..10` distinct complete `DirectReceivedMediaActionIdentity` values.
- Empty, over-cap, duplicate complete identities, blank/whitespace contact scope, blank/whitespace message ID, blank/whitespace attachment ID, or a current parent outside that contact scope denies the whole request before a ready draft or operation token is exposed. `DirectReceivedMediaActionIdentity` permits raw strings, so Plan 249 must enforce these nonblank identity components itself.
- An attachment-ID collision never substitutes for the full `(messageId, attachmentId)` pair.
- Same-ID group and unresolved rows remain ineligible and unchanged.
- Selection/tap insertion order is not dispatch order and paths are never identity.

### Current-row qualification

- Call the landed `qualifyCurrentDirectMediaRow` for every exact identity with the current parent loader, direct-owner attachment repository, path resolver, and file-existence seam.
- That landed boundary remains authoritative for current incoming parent identity, hidden/deleted/corrupt/private/unsupported/terminal state, exact direct owner, download/integrity state, stored path, and local byte existence.
- Add only the Plan-249 requirements not owned by that qualifier: one contact scope, visual media (`image` or `video`), batch cardinality, atomicity, canonical ordering, captions, and per-item tokens.
- Do not call `DirectPrivateMediaActionEligibility.evaluate` as an alternate Plan-249 policy and do not accept an injectable permissive qualifier that can authorize a row denied by Plan 234.
- Initial build qualifies every source before token minting. Any source denial returns one batch denial and no partial draft.

### Canonical order and independent items

- Sort newest first by the exact SQL keyset:
  `(parent.timestamp DESC, message id DESC, attachment id DESC)`.
- Compare the persisted timestamp/key strings consistently with the current Shared Media repository ordering; do not use tap order, path, repository callback completion order, or parsed wall-clock fallback.
- Two attachments from one parent remain two items. They may begin with equal caption text but own independent caption values and independent tokens.
- Mint exactly one non-empty unique opaque token per attachment only after every source qualifies. A blank or colliding token fails the whole build rather than risking receiver dedup collapse.
- Source rows, parent text, attachment rows, local bytes, keys, and nonces are never mutated.

### Dispatch-time revalidation

- Re-read all exact sources immediately before Session 02 may dispatch anything.
- Recompute current eligibility, resolved path, and canonical order.
- Preserve caption and token by complete source identity; do not remint a token or restore the current parent caption over an edited/cleared caption.
- If one source changed contact scope, identity, owner, visibility, privacy/lifecycle state, download/integrity state, visual kind (including image/video becoming audio/file), path, or local-byte availability, deny the whole batch with no ready subset, no token remint, and no caption restoration.
- The revalidation API performs no picker launch, target load, upload, encryption, message creation, persistence, or send. Its ready result is merely the atomic dispatch opportunity consumed by Session 02.

## Exact Write Scope

### Owned in Session 01

- `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`
  - copy the accepted D-249-01..07 ledger from the breakdown;
  - replace stale `evidence-gated`, group/announcement, conditional schema/wire/device, and unresolved test language;
  - set overall Plan 249 to implementation-in-progress, not accepted;
  - record Session 01/02/03 ownership and this host-only proof profile.
- `lib/features/conversation/application/build_direct_media_library_batch_forward.dart` — new, sole production owner.
- `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart` — new causal suite.
- `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart` — add only the exact Session-01 action-absence preservation sentinel if it is not already present.
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md` — register/classify only the new causal suite in both 1:1 inventories.
- This session plan and the Plan-249 breakdown — execution/QA/closure evidence and the Session-01 ledger transition only.

### Read-only authorities and preservation sentinels

- `received_media_action_controller.dart`, especially `DirectReceivedMediaActionIdentity` and `qualifyCurrentDirectMediaRow`.
- `private_media_action_eligibility.dart` and its two Plan-234 causal/boundary suites.
- `build_received_media_forward.dart` and its Plan-232 test.
- `direct_media_library_controller.dart`, `media_library.dart`, `media_library_db_helpers.dart`, and existing direct library tests.
- `media_attachment_repository.dart` and current model types.
- `direct_shared_media_library_screen.dart` and `conversation_wired.dart` remain read-only in Session 01.

The landed qualifier already supplies every required current-row fact. If execution discovers that another production file must change, stop and amend/review this session plan; do not silently widen the write set.

## Strict Non-goals And Scope Guard

- No production Batch Forward action, callback, route, picker, preview, contact load, progress, result matrix, retry UI, or delivery call.
- No edit to `DirectSharedMediaLibraryScreen`, `ConversationWired`, ordinary `ShareTargetPickerWired`, or `ShareBatchDeliveryCoordinator`.
- No l10n/ARB/generated-l10n work; Session 02 owns user-visible copy.
- No group or announcement source/destination behavior and no Plans 250/251 work.
- No schema, migration, version, registry, table, column, durable batch state, or v101. Plan 238 retains sequential v101 after Plan-234 v100.
- No album, grouped message, shared caption, batch envelope, provenance array, receiver codec, encrypted-inner change, legacy fallback change, or receiver UI change.
- No Go/libp2p/relay, native Android/iOS, device, SQLCipher, notification, actual PiP, or media-viewer work.
- No Session-02 delivery/UX, Session-03 acceptance, Plan-234 Session-05/06, or excluded-plan work.
- No changes to Plan-232 one-source Forward behavior or Plan-233 Save/Share/Delete/Bookmark/Viewer/Go-to-message behavior.
- No `core-host-all`, `feature-host-all`, performance-family, or full `host-all` run.

## RED-first Causal Test Contract

Add the new test file before the production file. The first causal command must fail because `BuildDirectMediaLibraryBatchForward` and its result/draft vocabulary do not exist. Preserve that RED output in `## Execution Progress`; do not replace it with a prose claim or add production stubs first.

| Case | Exact named behavior | Required proof / mutation |
|---|---|---|
| TC-249-S01-01 | `rejects empty over-cap duplicate blank-identity and cross-scope selections before token mint` | Empty, 11 items, duplicate complete identity, blank/whitespace contact, blank/whitespace message ID, blank/whitespace attachment ID, and a current parent from another contact all deny atomically. Mutation: accept/dedupe/truncate any invalid input and the test turns red. |
| TC-249-S01-02 | `qualifies every exact current direct visual source atomically` | Ordinary current incoming image/video rows pass; missing/replaced/deleted/hidden/outgoing/private/protected/unsupported/consumed/expired/pending/failed/integrity-failed/evicted/missing-path/missing-byte/nonvisual/wrong-owner/unresolved/group rows deny with no partial draft. A permissive secondary seam cannot bypass the landed central policy. |
| TC-249-S01-03 | `sorts reverse tap order and same-parent siblings by the canonical library keyset` | Reverse input plus equal-timestamp/equal-parent fixtures produce timestamp/message/attachment descending order. Same-parent siblings remain separate. Mutations to tap/path/ascending order or parent coalescing fail. |
| TC-249-S01-04 | `creates independent captions and unique opaque tokens per attachment` | Each item starts with its current parent caption; sibling edits/clears do not affect another item; tokens are non-empty and unique. Blank/colliding token factories deny the whole build. No source row/text changes. |
| TC-249-S01-05 | `dispatch revalidation preserves edited captions and tokens while refreshing paths scope kind and order` | Revalidation reloads every identity, refreshes eligible path/order/scope/visual kind, preserves caption/token by full identity, and mints no new token. Mutations that remint, restore parent text, retain a stale path, accept a changed contact, or accept audio/file fail. |
| TC-249-S01-06 | `one source scope kind or eligibility race denies the whole revalidation with no ready subset` | Replace/private/delete/evict one source, change its parent `contactPeerId`, or replace its visual row with audio/file after preview; the result contains no ready subset, remints no token, restores no caption, and exposes no dispatch opportunity. Mutation to eligible-subset continuation fails. |
| TC-249-S01-07 | `draft and denial diagnostics expose no source payload or media secrets` | No serialization/diagnostic includes sender identity, contact payload, caption history, path, key, nonce, bytes, or provenance token. Local draft fields are not logged or serialized. |
| TC-249-S01-08 | `batch forward stays absent while only draft preflight is landed` | Shared Media continues to expose existing Save/Share/Delete/Go-to-message behavior with no Batch Forward control/callback/navigation. Mutation that wires or renders the action fails. |

Preservation sentinels must also prove:

- Plan-232 one-source Forward still reloads before token/path/picker work and retains its single explicit-action token semantics.
- Plan-234 private/terminal/unsupported/corrupt states still fail closed through the exact-current boundary.
- Plan-233 ten-item selection, external batch actions, failed-only reconciliation, canonical library paging, same-ID sibling protection, and existing action bar remain unchanged.

## Implementation Sequence

1. Capture the fresh dirty-tree, scoped hash, missing-new-file, and forbidden-scope baselines.
2. Refresh only the source Plan-249 decision/status/test/proof contract from the accepted breakdown. Do not mark Plan 249 accepted.
3. Add TC-249-S01-01..07 and the exact action-absence sentinel before production.
4. Run and record the causal new-suite RED caused by missing production API.
5. Implement the immutable application-only draft/result/builder in the single new production file, reusing `qualifyCurrentDirectMediaRow`.
6. Reach focused GREEN; make only test-fixture corrections that reflect real current contracts and record any triage.
7. Register the new test file in both 1:1 arrays and the gate-definition document.
8. Run every literal focused, curated, inventory, completeness, static, and scope gate below.
9. Run final Graphify `affected` over the attributable production file.
10. Obtain fresh independent QA. Apply at most two bounded fix passes; after any fix rerun its causal tests, preservation sentinels, curated gate, static/scope checks, and final `affected`. A finding requiring UI/delivery/schema/wire/native/group scope blocks and re-plans rather than widening Session 01.
11. Only after final QA accepts, run exactly one incremental architecture refresh.
12. Persist `## Execution Result`, then run the closure-audit workflow and synchronize only Session-01 source/breakdown status. Unblock Session 02; do not close Plan 249.

## Literal Acceptance Gates

Run every command from the repository root. Record exact exit status and test count/output in `## Execution Result`.

```bash
# Fresh shared-tree and scoped baseline before RED.
git status --short
test ! -e lib/features/conversation/application/build_direct_media_library_batch_forward.dart
test ! -e test/features/conversation/application/build_direct_media_library_batch_forward_test.dart

# Causal RED first; rerun as the primary GREEN after implementation.
flutter test test/features/conversation/application/build_direct_media_library_batch_forward_test.dart

# Landed Plan-234 exact-current policy/boundary preservation.
flutter test test/features/conversation/application/private_media_action_eligibility_test.dart test/features/conversation/application/direct_private_media_boundary_test.dart test/features/conversation/application/received_media_action_controller_test.dart

# Plan-232 one-source Forward preservation.
flutter test test/features/conversation/application/build_received_media_forward_test.dart

# Plan-233 selection/batch/current-row preservation.
flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart test/features/conversation/application/direct_media_library_boundary_test.dart

# Session-01 production-action absence.
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'batch forward stays absent while only draft preflight is landed'

# Affected curated lane and registration/completeness truth.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check

# New-file registration must appear in both arrays and the definition doc.
rg -n 'build_direct_media_library_batch_forward_test\.dart' scripts/run_test_gates.sh scripts/run_host_test_gates.sh Test-Flight-Improv/test-gate-definitions.md

# Scoped formatting and analysis.
dart format --output=none --set-exit-if-changed lib/features/conversation/application/build_direct_media_library_batch_forward.dart test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
dart analyze lib/features/conversation/application/build_direct_media_library_batch_forward.dart test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart

git diff --check

# Baseline-safe forbidden-scope comparison. Record this exact list before RED
# and after GREEN; Session 01 may add no path even when baseline paths exist.
git diff --name-only -- lib/core/database/migrations lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart android ios go-mknoon go-relay-server lib/features/groups lib/features/announcements lib/l10n lib/features/share lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart

# Final attributable production impact, after all fixes and before final QA.
python3 graphify-arch/tdd_context.py affected lib/features/conversation/application/build_direct_media_library_batch_forward.dart --budget 600
```

The two `test ! -e` commands are pre-RED evidence only and are not rerun after the files are intentionally created. Every other applicable command must be fresh on the final candidate. Full `host-all` is explicitly not a Session-01 gate.

## Independent QA And Refresh Contract

- QA must be fresh and independent of the implementation pass.
- Review the final source-plan refresh, builder/result API, causal tests, action-absence sentinel, registrations, complete attributable diff, baseline-safe forbidden scope, and Graphify `affected` output.
- Required counterexamples: permissive qualifier, stale/replaced parent, cross-contact identity at build and after preview, same-ID owner collision, one private/terminal source among ordinary sources, reverse input, same-parent siblings, duplicate identity, blank/whitespace message or attachment IDs, blank/colliding token, caption clear/edit, path change, visual-to-audio/file replacement after preview, one-source revalidation failure without token remint/caption restoration, and accidental action wiring.
- Acceptance requires no unresolved blocking finding and no unsupported delivery/UI/schema/wire/device claim.
- `fix_passes` starts at zero and is recorded. At most two bounded passes are authorized inside this exact scope.
- After final QA accepts, run exactly once:

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

- Do not refresh before QA acceptance and do not run a second refresh for closure-document edits.

## Done Criteria

- [x] Fresh dirty-tree, scoped hash, missing-file, and forbidden-scope baselines are recorded without altering shared work.
- [x] Source Plan 249 contains the accepted D-249-01..07 direct-only ordinary-send contract and is no longer evidence-gated, while overall Plan 249 remains open.
- [x] The first causal builder command is recorded RED before production exists.
- [x] Exactly one new production file owns the immutable draft/preflight foundation.
- [x] Build accepts only `1..10` distinct exact identities from one direct contact scope.
- [x] Every current source is qualified through the landed Plan-234 exact-current boundary; all ineligible states deny atomically.
- [x] Canonical timestamp/message/attachment descending order, same-parent separation, visual-only eligibility, independent captions, and unique per-item tokens are causal-tested.
- [x] Dispatch revalidation preserves edited/cleared captions and tokens, refreshes path/order, and exposes no partial ready subset on any source race.
- [x] Draft/result diagnostics and representations expose no forbidden payload, attribution, path, key, nonce, byte, caption-history, or token data.
- [x] Production Batch Forward remains absent and every Plan-232/233/234 preservation sentinel passes.
- [x] The new causal suite is registered in both 1:1 arrays and the gate-definition doc.
- [x] Every literal focused, curated, inventory, completeness, formatter, analyzer, diff, and baseline-safe scope gate passes.
- [x] Final Graphify `affected` covers the attributable production file.
- [x] Fresh independent QA accepts after no more than two recorded fix passes.
- [x] Exactly one incremental Graphify refresh runs after QA acceptance.
- [x] `## Execution Result` and closure audit truthfully record evidence, Session 02 alone becomes runnable, and Plan 249 remains implementation-in-progress.

## Closure-document Update Contract

Only after accepted execution, final QA, and the one post-QA refresh:

- Set this session plan to `Status: accepted`, check only truthful Done Criteria, append `## Execution Result`, and add a stable `## Closure Audit`.
- Update the Plan-249 source plan with Session-01 execution evidence and status. Keep Sessions 02–03 open and the overall verdict `still_open` / implementation-in-progress.
- Update the Plan-249 breakdown Session-01 ledger row to accepted, Session 02 to pending/runnable, and Session 03 to prerequisite-blocked only on Session 02; do not rewrite the settled D-249 decisions.
- Retire the breakdown's stale `Structural Blockers Remaining`, arbiter, and dependency wording that says Plan-234 Session 04 has not landed. Record that the external prerequisite is satisfied and no longer blocks Plan 249, while overall Plan 249 remains open for Sessions 02-03.
- Keep `00-INDEX.md` and `19-1to1-message-reliability-closure-reference.md` for Session 03 final synchronization.
- Run a separate closure review for evidence fidelity, overclaim, residuals, and dependency correctness. Reopen Session 01 only for a causal regression in its source-plan/draft/preflight/registration boundary.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 18:10 CEST | execution preflight captured | `git status --short`; 20-file scoped hash; new-file absence checks; literal forbidden-scope guard | Shared dirty baseline preserved. Aggregate `2cf58536abfdf0db15ece27e655e454cee1e5c02130d618157a043f3e74bb4b6`; builder/test absent; forbidden output contains only the recorded pre-existing version/registry, Session-04 presentation, group-repository, and l10n paths. No production/test/gate/source-plan edit has begun. | obtain independent plan review, refresh the source contract, then author causal REDs |
| 2026-07-11 18:16 CEST | executor baseline re-snapshot | same 20-file scope; both `test ! -e` checks; literal forbidden-scope guard | Fresh executor aggregate `cc8ea0a1b49083cc9781ae81968c3b85957eb3fa694904aca4218000336e20ca`; both new paths absent; forbidden output remained exactly the 13 recorded pre-existing paths. Shared dirty work was not reset, stashed, reverted, or attributed to Plan 249. | refresh only the source plan, then author REDs |
| 2026-07-11 18:18 CEST | accepted source contract refresh | `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md` | Replaced stale evidence-gated/conditional album, group, schema, wire, and device language with accepted D-249-01..07 direct-only ordinary-send composition. Overall Plan 249 remains `implementation-in-progress`; Sessions 02-03 remain open. | add tests before production |
| 2026-07-11 18:20 CEST | causal tests authored and RED captured | new `build_direct_media_library_batch_forward_test.dart`; exact action-absence sentinel; `flutter test test/features/conversation/application/build_direct_media_library_batch_forward_test.dart` | Intended RED, exit `1`: import failed because `lib/features/conversation/application/build_direct_media_library_batch_forward.dart` did not exist; `BuildDirectMediaLibraryBatchForward`, result/draft vocabulary, and denial enum were undefined. No production stub existed. | implement the sole production owner |
| 2026-07-11 18:22 CEST | focused GREEN | new `build_direct_media_library_batch_forward.dart`; causal suite | Exactly one production file now owns immutable item/draft/result vocabulary, mandatory `qualifyCurrentDirectMediaRow` delegation, full-identity/cardinality/contact/visual validation, canonical sort, post-qualification tokens, and atomic revalidation. Primary suite passed `7/7`. | register and run preservation gates |
| 2026-07-11 18:23 CEST | registrations and preservation | both 1:1 arrays; gate definitions; exact Plan-234/232/233/action-absence commands | Registration present in all three authorities. Plan 234 passed `19/19`; Plan 232 passed `2/2`; Plan 233 passed `7/7`; action absence passed `1/1`. No production action/callback/route was added. | curated and static gates |
| 2026-07-11 18:25 CEST | bounded executor counterexample refinement | builder and causal suite | Re-probed the exact resolved path returned to the draft and added post-preview replaced-parent, wrong-owner, missing-path, and missing-byte races. This was executor refinement before independent QA, not a QA fix pass. Causal suite remained `7/7`; scoped analysis remained clean. | rerun every final-candidate gate |
| 2026-07-11 18:27 CEST | final Executor gates | literal focused commands; `./scripts/run_test_gates.sh 1to1`; host `--list`; completeness; registration `rg`; formatter/analyzer; diff/scope guards | Final causal `7/7`; Plan 234 `19/19`; Plan 232 `2/2`; Plan 233 `7/7`; absence `1/1`; curated 1:1 `1,909/1,909`; host inventory `81`; completeness `1,167/1,167`; formatter `0 changed`; analyzer `No issues found`; `git diff --check` clean; forbidden scope exactly matched the 13-path baseline. | run final affected and hand off to independent QA |
| 2026-07-11 18:27 CEST | final Graphify impact | `python3 graphify-arch/tdd_context.py affected lib/features/conversation/application/build_direct_media_library_batch_forward.dart --budget 600` | Exact impact surfaced only `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart`. No refresh ran. | independent QA; `fix_passes=0` at handoff |
| 2026-07-11 | fresh independent QA | Final attributable production/test/registration/source-plan diff, required counterexamples, literal evidence, scope baseline, and `affected` output | `ACCEPTED`; no blocking or non-blocking findings; `fix_passes=0`. QA authorized exactly one incremental architecture refresh. | run the one authorized refresh, then close Session 01 |
| 2026-07-11 | post-QA architecture refresh | `./graphify-arch/refresh_arch_graph.sh --incremental` | Exit `0`; five changed code files and 2,476 unchanged files processed; graph now has 47,439 nodes / 73,722 edges and the deterministic overlay has 1,260 files / 12,332 named tests / 953 production targets. This was the sole Session-01 post-QA refresh. | persist execution result and closure audit |

## Historical Executor Handoff (Pre-QA)

- **Historical executor verdict at handoff:** implementation and proportional
  evidence were complete; Session 01 was awaiting fresh independent QA and
  Session 02 was not yet unblocked. The later QA, refresh, Execution Result, and
  Closure Audit below supersede only that interim status; Plan 249 remains open.
- **Attributable production:** only
  `lib/features/conversation/application/build_direct_media_library_batch_forward.dart`
  (SHA-256
  `e7724ce6c90b31f1b2ba887e63db84ecebbb223a770ba69a68e64b3a0e4cf8c1`).
- **Attributable causal proof:**
  `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart`
  (SHA-256
  `11cac79d3d144050ba2ecc80ae43e40cac736aa4b05dd2708728bc56283beb86`)
  and the exact action-absence sentinel in the pre-existing Shared Media suite.
- **Contract/registration edits:** refreshed source Plan 249, both 1:1 arrays,
  and `Test-Flight-Improv/test-gate-definitions.md`. The Session-01 breakdown
  was not transitioned; closure owns that change.
- **Final evidence:** causal `7/7`; Plan-234 authority `19/19`; Plan-232
  Forward `2/2`; Plan-233 library preservation `7/7`; absence sentinel `1/1`;
  curated 1:1 `1,909/1,909`; host inventory `81`; completeness
  `1,167/1,167`; scoped format/analyze, diff hygiene, registration, and
  baseline-safe scope checks all passed.
- **Scope truth:** the post-GREEN forbidden list is identical to the pre-RED
  list: version/registry, Session-04 `conversation_wired.dart` and
  `direct_shared_media_library_screen.dart`, two group-repository files, and
  seven l10n files. These are shared pre-existing changes; Plan 249 added none.
- **Independent QA focus:** permissive-policy bypass absence, complete-identity
  collisions, token mint timing/collision, canonical descending string order,
  same-parent separation, caption/token preservation, contact/kind/path/byte
  races, diagnostic redaction, and accidental production action wiring.
- **QA/closure state:** `fix_passes=0`; no independent QA finding required a
  fix. Fresh independent QA accepted, the one authorized
  incremental Graphify refresh completed, and the closure record below
  transitions only Session 01. Overall Plan 249 remains open.

## Execution Result

`accepted`

- RED-first history is intact: the first causal run exited `1` only because the
  production API/file did not exist; production was added afterward.
- Final focused proof passed: causal builder `7/7`; Plan-234 current-row
  preservation `19/19`; Plan-232 Forward `2/2`; Plan-233 library preservation
  `7/7`; Session-01 production-action absence `1/1`.
- Final proportional gates passed: curated `1to1` `1,909/1,909`; host inventory
  `81`; completeness `1,167/1,167`; registration present in both arrays and the
  definition document; formatter changed zero files; scoped analyzer reported
  no issues; `git diff --check` was clean.
- The forbidden-scope output remained exactly the recorded 13-path shared
  baseline. Plan 249 Session 01 added no schema/version/registry, share UI,
  group, announcement, native, Go/relay, device, or l10n scope.
- Graphify `affected` covered the sole attributable production file. Fresh
  independent QA accepted with `fix_passes=0`, then exactly one incremental
  architecture refresh completed successfully.
- The hidden foundation remains non-user-visible. Session 02 alone is now
  runnable; Session 03 and overall Plan 249 remain open.

## Closure Audit

- **Evidence fidelity:** exact RED/GREEN, focused, curated, inventory,
  completeness, static, scope, QA, and refresh evidence is recorded above; no
  full `host-all`, device, migration, wire, relay, or native claim is made.
- **Behavioral boundary:** one immutable application builder owns atomic
  exact-current qualification, canonical order, independent captions/tokens,
  and all-or-nothing revalidation. No production Batch Forward action exists.
- **Shared-worktree safety:** unrelated dirty paths were preserved and the
  baseline-safe forbidden list did not grow.
- **Dependencies:** accepted Plan-234 Session 04 remains the current-row
  authority. Session 02 is runnable; Session 03 remains blocked only on Session
  02. Plan 249 remains `implementation-in-progress`.
- **Reopen rule:** reopen Session 01 only for concrete regression evidence in
  its source contract, draft/preflight builder, registrations, or action-absence
  sentinel.
- **Separate Closure Reviewer:** `ACCEPTED` after one documentation correction
  pass. The reviewer verified evidence fidelity, the historical pre-QA handoff,
  the satisfied Plan-234 prerequisite, the sole Session-02 runnable state, and
  the still-open overall Plan-249 verdict; no residual closure blocker remains.
