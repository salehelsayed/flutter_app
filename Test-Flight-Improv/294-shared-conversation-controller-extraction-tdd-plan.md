# 294 - DTR-15 shared conversation controller extraction

Status: Plan-green / Wave-accepted; implementation-complete 2026-07-28
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-15`)
Classification: Plan-green / Wave-accepted
Closure tier: host
Roadmap ID / wave: `DTR-15` / Wave 4B — Bootstrap and conversation seams
Owner authorization: `DTR15-AUTH-01`; after the planning/review request, the
current project owner explicitly ordered Codex to set the implementation goal
and implement this plan.
Date: 2026-07-28

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-28 CEST | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | The required TDD-profile query anchored both Wired screens at current fingerprint `c4692c00a63044ee`; direct test and performance details required targeted source verification. | Verify ownership, deliberate asymmetries, public APIs, and gate registration in current source. |
| 2026-07-28 CEST | Evidence Collector — production | both Wired screens; composer, recording, upload, and reaction models | Both private `State` objects own near-duplicate presentation mechanics, but send, cancellation, auto-stop, reaction-result, and group-rebind policies differ. Composition through typed lane ports is viable; a shared `State` is not. | Bound four controller seams and name explicit non-goals. |
| 2026-07-28 CEST | Evidence Collector — proof | direct/group Wired suites; structural integration tests; gate scripts; performance tests/harnesses | Direct/group widget coverage is broad, but direct total-budget overflow and group valid-auto-stop negative outcomes are not pinned. `performance-host` has no Wired/controller contract, and the integration performance harnesses have no hard controller-regression threshold. | Add causal controller tests, two preservation closures, and a deterministic notification-budget performance test. |
| 2026-07-28 CEST | Planner | roadmap; TDD tier/template/sufficiency references; dirty-tree snapshot; DTR-12 checker | Host closure is sufficient because the plan changes presentation ownership only. New shared presentation files can live under the already-classified `lib/shared/widgets/**` surface without rebaselining DTR-12. Plan 293 was concurrently claimed by DTR-14, so the rechecked next free number is 294. | Run the requested independent `$tdd-review` before any implementation authority is sought. |
| 2026-07-28 CEST | Reviewer — independent verifier plus main synthesis | Plan 294; both Wired screens; exact API ranges; upload/wake lifecycle; reaction admission; gate dispatchers; Flutter rebuild instrumentation | Initial verdict `plan-fixes-required`: the direction is sound, but seven contracts could pass with ceremonial ownership, wrong lifecycle wiring, incomplete API/registration checks, or controller-only performance proof. The live group reaction filter claim was also broader than current source. | Apply only the verified deltas, rerun all five lenses, and retain the separate execution-authority guard. |

## Problem And Evidence

- Behavior to improve: direct and group conversations must compose shared,
  independently testable presentation controllers while preserving their
  current public widgets, screen handoffs, and deliberately different lane
  policies.
- Impact:
  `lib/features/conversation/presentation/screens/conversation_wired.dart` is
  7,099 lines with 114 imports, and
  `lib/features/groups/presentation/screens/group_conversation_wired.dart` is
  7,767 lines with 120 imports. Exactly 64 import directives are identical at
  this planning snapshot. The screens duplicate mutable composer, upload,
  recorder, and reaction-projection mechanics inside two very large `State`
  objects, which makes lifecycle and rebuild regressions difficult to isolate.
- Confirmed current gap:
  - `_ConversationWiredState extends State<ConversationWired> with
    WidgetsBindingObserver` at `conversation_wired.dart:500-501` directly owns
    pending attachments/composer notifier, recorder subscriptions and
    waveform state, reactions, upload progress, active cancellation, and their
    cleanup;
  - `_GroupConversationWiredState extends State<GroupConversationWired> with
    WidgetsBindingObserver` at `group_conversation_wired.dart:419-420` owns the
    parallel state and additionally retargets it through
    `didUpdateWidget`/`_resetForGroupChange`;
  - there is no shared conversation-controller module or composition contract.
- Confirmed safe seams:
  - upload event projection/tracking is nearly identical at
    `conversation_wired.dart:1200-1443` and
    `group_conversation_wired.dart:871-1075`;
  - composer publication and semantic equality are parallel at
    `conversation_wired.dart:5520-5622` and
    `group_conversation_wired.dart:4570-4656`;
  - recorder callback/subscription/buffer ownership is parallel around
    `conversation_wired.dart:4692-5206,6693-6703` and
    `group_conversation_wired.dart:4744-5457,7531-7545`;
  - incoming reaction projection shares the same one-reaction-per-sender
    reducer at `conversation_wired.dart:5312-5462` and
    `group_conversation_wired.dart:7278-7488`.
- Confirmed differences that must not be normalized:
  - direct upload cancellation persists direct/private
    `upload_cancelled` state; group cancellation fails only pending group
    leaves while preserving completed serialized leaves;
  - direct private-media eligibility/policy is part of composer projection;
    group authoring remains ordinary-only;
  - a valid direct recorder auto-stop is retained for explicit send/discard
    review; group returns to idle and does not expose review or auto-send;
  - direct reaction transport is 1:1 durability; group persisted-reaction
    hydration qualifies ordinary messages, while outbound group reactions have
    replay-outbox `queuedForRetry` and dissolved/removed/unavailable terminal
    behavior. Current group live-stream admission at
    `group_conversation_wired.dart:7307-7330` does not apply that persisted-load
    filter and is not reclassified by this extraction;
  - direct releases its send lock after durable optimistic save, while group
    holds its send-flow lock through cleanup.
- Existing coverage:
  - direct and group Wired suites cover initial media hydration, invalid
    attachments, upload progress/leave/cancel, recording ticks, recorder
    displacement, reactions, and disposal;
  - `conversation_wired_change_coalesce_test.dart` and group
    `TC-159-08`/`TC-159-08b` pin frame coalescing and sorting side effects;
  - `group_private_media_preupload_boundary_test.dart`,
    `android_group_media_reliability_controller_test.dart`, and the P268
    ordinary-only source contract pin security-sensitive group ownership.
- Missing coverage:
  - no causal test requires controller composition or forbids a shared base
    `State`;
  - direct has no Wired test for individually valid attachments whose combined
    bytes exceed the message budget;
  - the group auto-stop test proves idle/handler cleanup but not zero send,
    absence of direct-style review controls, or the current non-deleting file
    ownership;
  - no Wired test retargets a group while an attachment upload is active, and
    `_resetForGroupChange` does not currently reset upload tracking, active
    cancellation, or the upload progress subscription;
  - `performance-host` currently selects `test/performance/**` but no selected
    test imports either Wired screen or a conversation controller.
- Refuted findings:
  - 64 common imports and 59 common private method identifiers do not prove
    interchangeable behavior; the lane differences above refute a shared
    inheritance hierarchy or broad controller with direct/group switches;
  - the existing direct integration performance harnesses are supporting
    diagnostics, not DTR-15 closure: they collect reports without a hard
    controller-notification threshold and do not cover the group surface;
  - ordinary-only group reaction admission is confirmed for persisted loads,
    not for live changes. The shared reaction seam is therefore only the pure
    same-sender projection reducer; repository loads, subscriptions, admission,
    and transport remain lane-owned;
  - background-task leases, message coalescers, and complete reaction send
    flows are not safe shared seams in this plan.
- Confirmed deferred finding: a valid group auto-stop result is currently
  dropped from composer state, but current source does not explicitly delete
  its file. DTR-15 pins that current ownership as a preservation sentinel so it
  cannot silently absorb a cleanup change; correcting the possible orphan is a
  separately scoped follow-up.
- Affected production, test, and gate files:
  both Wired screens; new
  `lib/shared/widgets/conversation/*_controller.dart`; controller tests under
  `test/features/conversation/presentation/controllers/**`; the two existing
  Wired suites; the three exact structural/security tests named above; a new
  `test/performance/conversation_controller_notification_budget_test.dart`;
  `scripts/run_test_gates.sh`; `scripts/run_host_test_gates.sh`; this roadmap
  and index.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `c4692c00a63044ee`; current.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-15 extract shared direct/group conversation controllers from conversation_wired.dart group_conversation_wired.dart without shared base State; preserve facades/widget APIs; tests and 1to1 groups feature-host-all performance-host registrations" --profile tdd --budget 700`.
- Anchors:
  `lib/features/conversation/presentation/screens/conversation_wired.dart` and
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`.
- Surfaced proof/gate files: group conversation/application suites and related
  conversation/media owners; gate and direct-performance coverage required
  source verification.
- Graph gaps requiring source search: exact import counts, direct test
  selectors, private/group policy differences, dual 1:1 gate inventories,
  dynamic performance discovery, brittle source-locks, and integration harness
  thresholds.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add four plain compositional presentation controllers under
  `lib/shared/widgets/conversation/`:
  - `conversation_composer_controller.dart` owns the existing
    `ConversationComposerViewState` notifier, semantic equality, common
    pending-media/draft snapshot mechanics, and exact-once publication;
  - `conversation_upload_activity_controller.dart` owns the upload-progress
    subscription/projection, aggregate and per-message progress,
    active-upload/cancel-request state, late-event suppression, and view
    rebind/reset mechanics. Each begun upload returns an immutable
    scope-capturing operation handle that owns its wake-lock hold until the
    asynchronous upload, cancellation, or failure actually terminates;
  - `conversation_voice_capture_controller.dart` owns recorder callback
    identity, duration/amplitude subscriptions, waveform sampling, arming
    abort, stop/cancel mechanics, and session-scoped disposal;
  - `conversation_reaction_projection_controller.dart` owns only the reaction
    map, semantic publication, and pure same-sender replace/remove reducer.
    Repository loads, stream subscriptions/admission, and all outbound work
    remain in each Wired adapter.
- Keep both private Wired `State` classes as composition roots. Each constructs
  and disposes the same controller types and supplies small typed closures or
  ports for lane behavior; no controller receives `BuildContext`, a Wired
  widget, or a `State`.
- Require real ownership transfer, not ceremonial fields:
  - both States lose their `List<PendingComposerMedia>` and
    `ValueNotifier<ConversationComposerViewState>` owners;
  - duration/amplitude subscriptions, `AmplitudeBuffer`, waveform samples, and
    pending recorder-abort state move to the voice controller;
  - the reactions map moves to the reaction controller, while each
    `ReactionChange` subscription stays lane-local;
  - the media-upload progress subscription, tracking booleans/counters/current
    ID, per-message progress map, active-upload snapshot, and cancel-request
    state move to upload ownership;
  - direct private policy and held-review recording, group restored media/voice
    continuations, navigation/dialog state, and all lane repositories remain in
    their current States.
- Screen handoffs and event paths must read controller-owned values/delegates.
  Composer/voice updates flow only through the existing composer listenable.
  Upload and reaction values use one merged, paired add/remove parent
  invalidation bridge per Wired State; there is no parallel voice `setState`
  bridge or duplicate controller listener.
- Keep these lane policies in the two Wired adapters:
  - attachment validation and direct private-policy normalization;
  - active visual-upload owner resolution, repository mutation, composer
    restore, localized feedback, and direct/group cancellation finalization;
  - direct review versus group drop/no-review auto-stop outcomes;
  - reaction load/subscription admission and every outbound
    send/remove/result/terminal path.
- Keep public model ownership unchanged:
  `ConversationComposerViewState` remains in `conversation_screen.dart`,
  `VoiceRecordingState` remains in `compose_area.dart`, and
  `UploadProgressViewState`/`MessageUploadProgressViewState` remain in
  `upload_progress_banner.dart`.
- Preserve `ConversationWired` and `GroupConversationWired` constructors,
  static keys/debug counters, callbacks, and their existing
  `ConversationScreen`/`GroupConversationScreen` handoffs. Do not add public
  controller injection parameters. Freeze the complete AST signature: parameter
  order/name/type/requiredness/default expression, static key literal, counter
  declaration, and exact named screen-prop mapping.
- Migrate source contracts to exact new owners without weakening their
  security/order assertions. A controller extraction must not make a
  wired-file substring test pass merely because the guarded state moved.
- Add a deterministic controller notification/invalidation budget under
  `test/performance/**`. It pumps both real Wired bindings and uses Flutter's
  debug-only `debugOnRebuildDirtyWidget` hook to count actual Wired-root
  rebuilds without adding a production debug counter or widget parameter.
  Run `performance-host` as a required DTR-15 per-plan, Wave 4B, and final
  closure gate.

Must preserve:

- Direct composer media budgets, private-policy restore, quote/draft restore,
  and invalid attachment behavior -> direct Wired media tests plus the new
  direct total-overflow sentinel.
- Group ordinary-only authoring, media budgets, restored continuation, and
  `_canWrite` gating -> P268 source contract and group composer tests.
- Direct/group upload owner qualification, monotonic progress, leave blocking,
  wake-lock reference count, and deliberately different cancellation
  finalizers -> both Wired upload suites and `upload_wake_lock_test.dart`.
  Detaching/unmounting suppresses UI publication but does not release an
  operation-owned wake hold early; terminal completion releases that exact hold
  once.
- Recorder ownership/displacement, write-loss/group-change cancellation, and
  direct-review versus group-no-review outcomes -> both recording lifecycle
  suites.
- Reaction-map reduction and ordinary incoming changes while persisted-load
  qualification, subscriptions, and all outbound direct/group durability and
  terminal semantics remain lane-local -> both reaction suites.
- One-per-frame message batching, ordering, scroll restoration, read marking,
  and intro/group recovery -> direct coalescer suite and group
  `TC-159-08`/`TC-159-08b`.
- Group retargeting: detach the old UI scope before binding new subscriptions,
  reject late old-group upload/reaction events, prevent old upload
  cancel/restore state from entering the new composer, and let the old
  operation release only its own wake hold when it terminates -> new Wired
  retarget tests plus controller operation tests.
- Public widget/facade API and all production call sites in `main.dart`,
  debug roots, Feed, Home, Orbit, Posts, and Create Group -> API composition
  contract plus `feature-host-all`.

Hard `Do not`:

- Do not create a shared base `State`, shared `State` mixin, common Wired
  superclass, inherited lifecycle, or controller that extends/implements
  Flutter `State`.
- Do not perform a big-bang rewrite. Extract one controller, wire direct, run
  focused direct proof, wire group, run focused group proof, then continue.
- Do not move widget constructors, public view models, static keys/debug
  counters, screen callbacks, dialogs, navigation, or `BuildContext` work.
- Do not share message load/pagination/sort/coalescing, send locks, durable
  message/media/voice publication, direct private-media lifecycle, group
  ACL/security/membership/read-only logic, route authorization, or background
  task leases.
- Do not place `if (isGroup)`, runtime message-type switches, or imports of
  either Wired screen in a shared controller. Differences enter through named
  typed ports and remain tested independently.
- Do not move reaction repository loads, stream subscriptions/admission, or
  transport into the shared reducer, and do not add a new live
  private-reaction policy under an extraction plan.
- Do not change schema, migration, crypto, wire, relay, native, notification,
  transport, or persisted-status semantics.
- Do not add or rebaseline a DTR-12 architecture exception, and do not absorb
  DTR-16 `GroupMessageListener` or DTR-18 relocation work.

Deferred / accepted difference:

- Message frame-flush scheduling remains lane-local because the post-flush
  side effects differ; existing coalescer tests are preservation sentinels.
- Background-task lease extraction remains deferred until direct refusal,
  throw, and unmount semantics are separately pinned.
- Reaction load/admission/transport/result handling remains lane-local; only
  the reaction map and pure reducer move.
- Group auto-stop file lifetime is a separate cleanup finding. DTR-15 pins the
  current valid capture as still present after group auto-stop, alongside zero
  auto-send/no review; a later cleanup plan must deliberately change that
  sentinel.

Dependencies:

- DTR-12 and Wave 4A are accepted; `DTR15-AUTH-01` authorized this bounded
  DTR-15 implementation.
- DTR-16 depends on the stable adapters produced here, but no
  `GroupMessageListener` decomposition is part of this plan.
- DTR-14 and DTR-15 form Wave 4B and are both Plan-green/Wave-accepted. The
  aggregate `host-all` and required same-tree `performance-host` replay passed;
  the retained receipt is [Wave 4B evidence](evidence/dtr-wave4b/README.md).
  Both gates remain mandatory again at final release closure.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-294-01 | Both Wired `State` classes remain direct `State<Widget>` composition roots and transfer the enumerated composer, upload, voice, and reaction-map owners into four real controllers; exact event paths/screen props consume controller outputs; controllers import neither screen nor `BuildContext` | `test/features/conversation/presentation/controllers/conversation_controller_composition_contract_test.dart::DTR-15 transfers exact owners without a shared State hierarchy` | Host AST/source contract / real repository | causal assertion RED: controller files are absent and the enumerated declaration types/subscriptions/maps remain in both States -> GREEN: those declarations are controller-owned, exact handlers/handoffs delegate to them, one paired invalidation bridge exists, and forbidden inheritance/imports are absent | retain or rename any enumerated owner in a State, add empty ceremonial controllers, bypass a controller at one screen prop/event path, duplicate a listener, or add common State inheritance -> TC-294-01 red | `flutter test --no-pub test/features/conversation/presentation/controllers/conversation_controller_composition_contract_test.dart --plain-name 'DTR-15 transfers exact owners without a shared State hierarchy'`; AUTO `feature-host-all`; add to `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS` |
| TC-294-02 | Composer controller owns common snapshots and publishes only semantic changes; direct policy remains adapter-owned and group remains ordinary-only | `test/features/conversation/presentation/controllers/conversation_composer_controller_test.dart::publishes only semantic composer changes and restores the exact common snapshot`; `::lane policy projection stays outside the shared controller` | Host unit / files plus direct/group fake policy closures | intentional compile RED after test addition: controller symbol absent -> GREEN: path-based list equality, snapshot round-trip, no-op zero notification, changed state one notification, and no lane branch | use list identity, omit quote/draft/pending state, publish a semantic no-op, or add direct/group policy logic to the controller -> TC-294-02 red | exact test file; AUTO feature family; add path to all three curated inventories named in TC-294-01 |
| TC-294-03 | Upload controller scopes monotonic progress, prunes stale owners, exposes active/cancel state, and creates an immutable operation handle whose wake hold survives view detach/rebind until terminal completion | `test/features/conversation/presentation/controllers/conversation_upload_activity_controller_test.dart::scopes monotonic progress and publishes once per accepted event`; `::detaching a view suppresses UI without releasing the operation wake hold`; `::cancel and terminal completion finalize and release the exact operation once` | Host unit / fake progress stream, owner resolver, wake driver, cancellation port, and old/new scope tokens | intentional compile RED: controller absent -> GREEN: exact projection, zero wrong-scope/regressive/late notification, one lane finalizer, no early detach release, one terminal release, and independent new-scope operation | accept wrong recipient/regressive bytes, retain a stale owner, release on view dispose, call finalizer/release twice, or apply an old-scope event after rebind -> TC-294-03 red | exact test file; AUTO feature family; add to both 1:1 inventories and `GROUP_TESTS` |
| TC-294-04 | Voice controller owns only its recorder session and returns one auto-stop outcome to the lane adapter without choosing direct review or group no-review behavior | `test/features/conversation/presentation/controllers/conversation_voice_capture_controller_test.dart::owns callbacks subscriptions and waveform only for its recorder session`; `::auto-stop emits one lane outcome without choosing review or discard` | Host unit / fake recorder, streams, permission, and outcome callback | intentional compile RED: controller absent -> GREEN: ordered arming/start/stop/cancel, bounded waveform, displaced-session no-op, late-event suppression, exact-once cleanup/outcome | cancel a displaced owner, retain a subscription, emit after dispose, choose review/drop inside shared code, or deliver auto-stop twice -> TC-294-04 red | exact test file; AUTO feature family; add to both 1:1 inventories and `GROUP_TESTS` |
| TC-294-05 | Reaction controller owns only the map and pure same-sender replace/remove projection; loads, subscriptions/admission, transport, retry, and terminal policy stay out | `test/features/conversation/presentation/controllers/conversation_reaction_projection_controller_test.dart::incoming change replaces or removes one sender without touching siblings`; `::semantic no-op publishes zero times and controller has no lane dependency` | Host unit / reaction maps and changes plus AST import check | intentional compile RED: controller absent -> GREEN: deterministic map/reducer, zero semantic no-op publication, and no repository/listener/bridge/Wired imports | append a duplicate sender, remove another sender/message, republish an identical map, or add repository/stream/transport policy to the controller -> TC-294-05 red | exact test file; AUTO feature family; add to both 1:1 inventories and `GROUP_TESTS` |
| TC-294-06 | Direct adapter preserves total-budget/private-policy behavior, upload restore/progress/unmount ownership, recorder review/ownership, reactions, and frame coalescing | `conversation_wired_test.dart::{1:1 total-size overflow (individually-valid attachments) shows a strip-level note and disables Send (no per-chip), upload failure restores quote draft and attachments, shows relay upload progress and blocks leaving mid-upload, disposing mid-upload detaches UI and terminal completion releases only its wake hold, recording ticks update composer without rebuilding the Wired root or message list, holds the recording for review and does not auto-send, disposing with a displaced recording session leaves the recorder untouched, incoming reactions refresh the open Orbit conversation and stay correct after reopen}`; full `conversation_wired_change_coalesce_test.dart` | Host widget / existing fakes, blocked upload, wake driver, and temp files | current sentinels GREEN; new total-overflow and mid-upload-unmount assertions are preservation GREEN on current logic -> remain GREEN through each direct adapter move | drop total overflow/private policy, release wake on view detach, use group cancel outcome, auto-send/drop direct capture, dispose another session, rebuild the Wired root on a tick, or move batching into a shared controller -> corresponding sentinel red | exact direct files; existing `ONE_TO_ONE_TESTS`/`ONE_TO_ONE_HOST_TESTS`; AUTO feature family |
| TC-294-07 | Group adapter remains ordinary-only and preserves total budget, upload restoration/progress, current auto-stop file ownership/no-review/no-auto-send, persisted-reaction qualification, ordinary live projection, repository switching, and coalescing | `group_conversation_wired_test.dart::{P268 group composer source has no private authoring API or mutable policy state, group total-size overflow (individually-valid attachments) shows a strip-level note and disables Send (no per-chip), upload failure restores quote draft and attachments, shows relay upload progress and blocks leaving mid-upload, recording ticks update composer without rebuilding the Wired root or message list, group recorder auto-stop preserves the capture file sends nothing and exposes no review controls, GPL-04E explicitly disabled resume hides durable private reactions while ordinary remains, incoming reaction change stream updates UI state, local status subscription switches when message repository changes, TC-159-08 group M-event burst → ONE batched reorder, all ids incl trailing, TC-159-08b coalesced group burst restores scroll offset once + marks read}` | Host widget/source / existing fakes plus a real temp auto-stop file | existing sentinels GREEN; strengthened auto-stop assertion is GREEN on current non-deleting/no-send/no-review behavior -> all remain GREEN after each group adapter move | expose private policy/review UI, delete or send the group auto-stop file, use direct cancellation, move load/admission policy into the reducer, retain old repository state, or change reorder/read counts -> corresponding sentinel red | exact group file; existing `GROUP_TESTS`; AUTO feature family |
| TC-294-08 | Wired lifecycle invokes controller detach/rebind/dispose in order: old upload/reaction events cannot mutate a retargeted group, old cancel/restore state cannot enter the new composer, ordinary same-binding sends survive route unmount, new events still work, and operation/recorder/wake resources remain owner-scoped | TC-294-03 unit cases plus `group_conversation_wired_test.dart::{DTR-15 durable two-leaf upload retarget and ABA unmount never resume the stale lane, old-group reaction after retarget is ignored while a new-group reaction applies, switching to another group cancels an active recording, DTR-15 completed voice stop retarget aborts at the gated preflight without crossing lanes}`; `group_conversation_wired_bg_task_test.dart::{ordinary media upload failure after unmount still persists failed parent status, ordinary media upload success after unmount still publishes and persists sent parent status}`; and direct unmount case in TC-294-06 | Host unit + real Wired widget / blocked old upload, old/new progress/reaction streams, shared recorder, fake wake driver | controller tests compile RED; group retarget is causal RED because current reset omits upload ownership/generation; the success-unmount and ABA mutations additionally RED on conflated mounted/binding lifetime -> GREEN with a captured send lane, monotonic binding generation, backend-continuation versus mounted-UI fences, new-scope liveness, and exact terminal release | omit/misorder one Wired lifecycle call, restore old composer state, accept an old event, starve the new stream, cancel the new recorder, stop an ordinary same-binding backend send at unmount, release on detach, or leak the old hold -> TC-294-08 red | exact controller, direct Wired, group Wired, and group background-task files; registrations inherited from TC-294-03/06/07 |
| TC-294-09 | Public `ConversationWired`/`GroupConversationWired` constructors, static keys/counters, callbacks, and screen handoffs are exact; security/order source contracts follow exact controller owners rather than becoming vacuous | `conversation_controller_composition_contract_test.dart::TC-294-09 freezes public Wired APIs and screen handoffs`; migrated `group_private_media_preupload_boundary_test.dart`, `android_group_media_reliability_controller_test.dart`, and P268 source contract | Host AST/source + compile/widget sentinels / literal current manifests | exact API fingerprint is GREEN on HEAD and remains GREEN; existing source locks are redirected/split to exact owners only when symbols move | change parameter order/name/type/requiredness/default, a key literal, counter declaration, create-state type, named screen prop mapping, or replace an exact-owner check with concatenated sources -> TC-294-09 red | exact feature controller/group application/integration files; API test enters all three curated inventories; other shared paths run directly |
| TC-294-10 | Controller extraction does not increase actual Wired invalidation fan-out: semantic no-ops/wrong-scope/regressive/late events rebuild zero Wired roots; one accepted upload or reaction event rebuilds its root at most once; a voice/composer tick rebuilds zero roots; message bursts still sort/reorder once | `test/performance/conversation_controller_notification_budget_test.dart::{semantic no-ops and irrelevant events rebuild neither Wired root, accepted upload and reaction events rebuild each Wired root at most once, voice ticks update composer without rebuilding either Wired root}` plus direct coalescer suite and group `TC-159-08`/`TC-159-08b` | Host deterministic performance widget contract / real direct and group Wired bindings, injected streams, controller listener counts, and `debugOnRebuildDirtyWidget` | intentional compile RED because controllers/bindings are absent while coalescer sentinels are GREEN -> GREEN with exact root-build and controller-publication budgets | remove semantic/scope guards, add a second listener, call page `setState` for voice, double-invalidate upload/reaction, or restore per-event sorting -> TC-294-10 red | exact performance file; AUTO `performance-host`; coalescer paths retain curated/feature registrations |
| TC-294-11 | Each of the five feature controller tests occurs exactly once in `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS`; feature/performance discovery sees the right globs; no architecture exception is added | `conversation_controller_composition_contract_test.dart::TC-294-11 gives DTR-15 tests exact curated gate membership`; feature/performance `--list`; `architecture-boundaries`, `runtime-roots`, and `completeness-check` | Host AST/source + process/tool / real scripts and repository | causal registration assertion RED until all 15 exact array entries exist -> GREEN with exact membership, automatic family discovery, and no exception/count drift | omit/duplicate one array entry, register only the host 1:1 array, place performance test outside its glob, or add/rebaseline an exception -> TC-294-11 red | composition contract plus literal commands below; exact manual arrays plus AUTO feature/performance globs |

### Test Notes

- TC-294-01 must assert each new production file exists before reading it so
  the first RED is an intentional assertion, not `PathNotFoundException`. It
  parses declarations/imports, forbids the enumerated owner types in each
  State, and proves exact event/handoff delegation. Identifier-only searches,
  LOC thresholds, common-import counts, or empty controller fields are
  insufficient.
- TC-294-02 snapshots only common draft/quote/pending-media state. Direct
  private policy remains a direct adapter value restored alongside the common
  snapshot; the group adapter must not gain hidden private state.
- TC-294-03 separates view lifetime from operation lifetime. Repeated equal
  bytes, regressive bytes, unknown owners, wrong recipient/scope, and
  post-detach events produce no publication; detaching does not release the
  wake hold, and only the retained operation handle may terminally release it.
- TC-294-04 tests the recorder callback by identity, matching current disposal
  guards. The group outcome discriminator is `send count == 0` and both
  `voice-review-send`/`voice-review-discard` absent. A real temp file remains
  present to pin current ownership; the separate cleanup follow-up must change
  that sentinel deliberately.
- TC-294-05 does not test a fabricated group-private live admission port.
  Current persisted-load and ordinary live behavior stay in the group Wired
  suite; only the reducer is shared.
- TC-294-09 embeds literal expected AST manifests for both constructors
  (order, name, type, requiredness, default initializer), static key literals,
  counter declarations, `createState` return, and named screen handoffs.
  Subset/name-only comparisons and joined-source strings are forbidden.
- TC-294-10 installs and restores `debugOnRebuildDirtyWidget`, settles each
  real fixture, zeros counters, then filters rebuild callbacks by
  `ConversationWired`/`GroupConversationWired` element widget type. Element
  identity and display-memo counters are not accepted as root-build proof.
- TC-294-11 parses the three readonly array declarations independently and
  asserts each exact path occurs once. Host `1to1 --list` cannot substitute for
  `ONE_TO_ONE_TESTS` or `GROUP_TESTS`.

## Implementation Steps

1. Snapshot `git status --short` and preserve every unrelated dirty path. Add
   the public-API GREEN sentinel and TC-294-01 assertion RED before production
   edits. Record that the failure is missing composition/remaining old
   ownership, not a missing fixture or unrelated compile error.
2. Composer slice:
   - add TC-294-02 RED;
   - implement `ConversationComposerController` with common snapshot and
     semantic publication only;
   - wire the direct State through its existing validation/private-policy
     adapter and run focused direct composer tests;
   - wire the group State through its ordinary-only adapter, update P268's
     exact-owner assertion, add the direct total-overflow sentinel, and run
     focused group composer tests.
   Stop-if common snapshot logic requires group private-authoring state, public
   model relocation, `BuildContext`, or a public widget parameter.
3. Upload slice:
   - add TC-294-03 RED;
   - move subscription/projection/active-cancel mechanics into
     `ConversationUploadActivityController`, with a separate immutable
     operation handle that captures lane scope, cancellation finalizer,
     composer snapshot, and one wake hold;
   - wire direct active-owner/cancel-finalization/restore ports, run direct
     upload tests, then wire group ports and run group upload tests;
   - on view dispose/group retarget, detach publication first but let the old
     asynchronous operation finish/release itself; guard every old
     cancel/restore callback by its captured generation;
   - add direct mid-upload unmount and group mid-upload retarget RED/GREEN
     proofs before accepting the group adapter.
   Stop-if repository status mutation, dialogs, localized snackbars, or durable
   media preparation must move into shared code, or if a view disposal would
   have to release an operation that is still running.
4. Voice slice:
   - add TC-294-04 RED;
   - move recorder-session identity, subscriptions, amplitude buffer, and
     stop/cancel mechanics into `ConversationVoiceCaptureController`;
   - wire direct auto-stop to the existing review state, then group auto-stop
     to idle/no-review/current non-deleting file ownership, adding the
     strengthened group outcome sentinel;
   - retain write-loss/group-change cancellation and displaced-owner guards.
   Stop-if direct/group voice publication or group file-lifetime policy would
   need to change.
5. Reaction slice:
   - add TC-294-05 RED;
   - extract only the reaction map, semantic publication, and same-sender
     change reducer;
   - leave direct filtering and group load/subscription admission unchanged in
     their States; generation-guard old-group callbacks during retarget;
   - leave every outbound optimistic transaction/result/terminal path in the
     corresponding State.
   Stop-if a shared controller needs a repository, listener/stream
   subscription, bridge, crypto, replay-outbox, group policy, or terminal
   read-only knowledge.
6. After each slice, migrate only source assertions whose exact owner moved.
   Preserve the private-media pre-upload ordering and Android reliability
   checks; do not delete or broaden them. Keep frame batching and send-flow
   fields in both States.
7. Add TC-294-10 with real minimal direct/group Wired fixtures. Count actual
   root rebuilds through `debugOnRebuildDirtyWidget`, prove composer/voice uses
   no parent invalidation and upload/reaction uses at most one, and retain
   controller publication plus coalescing budgets. Do not add public debug
   counters or use elapsed wall time, Element identity, display memo counts, or
   the non-threshold integration harnesses as the causal gate.
8. Add all five new feature controller test paths to `ONE_TO_ONE_TESTS`,
   `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS`. Make the composition contract
   assert all 15 exact memberships, verify feature/performance auto-discovery
   with `--list`, then execute the required focused, curated, family,
   architecture, analysis, and hygiene gates below.
9. After the authorized implementation is coherent and all code/tests settle,
   run `./graphify-arch/refresh_arch_graph.sh --incremental` once.

## Risks And Blind Spots

- Accidental shared inheritance or a disguised God-controller -> TC-294-01
  rejects State inheritance, screen/context imports, and retained extracted
  fields; typed lane ports keep policy at the adapters.
- Behavior normalization across siblings -> TC-294-02 through TC-294-07 pin
  direct private/group ordinary composer behavior, cancellation finalizers,
  current auto-stop file/outcome ownership, reaction-map reduction, and
  lane-owned reaction admission/result behavior separately.
- Late async callbacks after dispose/group change -> TC-294-03 through
  TC-294-05 and TC-294-08 require immutable operation/generation tokens, view
  detach before rebind, owner identity, terminal operation release, and
  late-event suppression.
- Rebuild/performance regression -> TC-294-10 makes `performance-host`
  count real Wired rebuilds and remain deterministic; controller-only counts,
  Element identity, and memo counters cannot false-green it.
- Source-lock false green after moved code -> TC-294-09 follows exact owners and
  forbids permissive concatenated-source checks.
- Public facade drift -> TC-294-09 plus production compile coverage in
  `feature-host-all`.
- Lifecycle / derived-state durability: group rebind and reopen hydration stay
  in the group State; TC-294-03/08 exercise the actual Wired lifecycle and
  existing hydration/repository-switch tests cover reconstruction without
  moving durable ownership.
- Sibling-surface consistency: TC-294-06/07 cover common mechanics and
  deliberately asymmetric policies with separate named sentinels.
- Destructive-action side effects: upload cancellation asserts the correct
  lane finalizer and preservation of completed group leaves/direct composer
  restore. TC-294-07 explicitly preserves the current group auto-stop file so
  DTR-15 cannot absorb the separate deletion decision.
- Invariant re-verification under new transitions: rebind/dispose tests
  re-check scope, owner, wake, recorder, and late-event invariants after reset.

## Gate Cadence

- Per-plan closure:
  - TC-294-01 causal assertion RED; TC-294-02 through TC-294-05 and TC-294-10
    intentional controller-symbol REDs, followed by focused GREEN and
    representative mutation re-reds;
  - exact direct/group Wired preservation and migrated security/source locks;
  - required curated `1to1` and `groups` gates;
  - required `feature-host-all`;
  - required `performance-host`, because both changed 7k-line Wired screens are
    performance surfaces and controller publication changes their invalidation
    fan-out;
  - architecture, runtime-root, completeness, strict-analysis, and diff gates.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure` once after
  the Wave 4B dependency batch (DTR-14 plus DTR-15) is Plan-green, followed by
  `./scripts/run_test_gates.sh performance-host --batch-flutter --concurrency 4 --reporter failures-only`
  against the same tested tree. Repeat both `host-all` and `performance-host`
  at final rollout/release closure. These are wave/final obligations, not
  additional per-plan `host-all` runs.
- Shared tests outside feature/core globs:
  `test/performance/conversation_controller_notification_budget_test.dart`
  runs exactly and through `performance-host`;
  `test/integration/android_group_media_reliability_controller_test.dart` runs
  exactly; group application source locks are auto-feature-discovered.

## Acceptance Gates

```bash
# Snapshot before authorized execution; record and preserve unrelated changes.
git status --short

# First causal RED before production edits: expect non-zero because the four
# controller files/composition fields do not exist and both States still own
# the mutable responsibilities.
flutter test --no-pub \
  test/features/conversation/presentation/controllers/conversation_controller_composition_contract_test.dart \
  --plain-name 'DTR-15 transfers exact owners without a shared State hierarchy'

# Add each controller test immediately before its slice. Each initially exits
# non-zero on the intentionally absent controller symbol, then exits 0 GREEN.
flutter test --no-pub \
  test/features/conversation/presentation/controllers/conversation_composer_controller_test.dart
flutter test --no-pub \
  test/features/conversation/presentation/controllers/conversation_upload_activity_controller_test.dart
flutter test --no-pub \
  test/features/conversation/presentation/controllers/conversation_voice_capture_controller_test.dart
flutter test --no-pub \
  test/features/conversation/presentation/controllers/conversation_reaction_projection_controller_test.dart

# Focused controller/API GREEN: exit 0, all semantic/negative assertions pass.
flutter test --no-pub \
  test/features/conversation/presentation/controllers

# Direct preservation: exit 0, including total-overflow, mid-upload unmount,
# review/displacement, reactions, voice root-build isolation, upload, and
# one-frame coalescing.
flutter test --no-pub \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_change_coalesce_test.dart

# Group preservation and exact moved-owner locks: exit 0; ordinary-only,
# cancellation, mid-upload retarget, old-event rejection, current auto-stop
# file/no-review/no-auto-send ownership, and coalescing stay exact.
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/groups/application/group_private_media_preupload_boundary_test.dart \
  test/integration/android_group_media_reliability_controller_test.dart

# Deterministic performance contract: exit 0; debugOnRebuildDirtyWidget records
# zero Wired-root rebuilds for no-op/rejected/voice events and at most one for
# each accepted upload/reaction event on both real bindings.
flutter test --no-pub \
  test/performance/conversation_controller_notification_budget_test.dart

# Registration checks: the focused composition contract above proves exact
# membership in all three arrays. These list commands independently prove the
# host-1:1 and automatic feature/performance plans; the normal curated gate
# executions below prove the non-host 1:1 and group tests run.
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_host_test_gates.sh feature-host-all --list
./scripts/run_host_test_gates.sh performance-host --list

# Required curated gates: each exits 0 with its final PASS; 1to1 and groups
# retain their registered Go tails.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Required affected family and performance sweeps: exit 0, zero failed tests.
./scripts/run_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_test_gates.sh performance-host \
  --batch-flutter --concurrency 4 --reporter failures-only

# Policy/discovery: exit 0; no new/stale exception or unclassified path.
./scripts/run_test_gates.sh architecture-boundaries
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check

# Hygiene: zero analyzer diagnostics attributable to DTR-15 and no whitespace
# errors.
./scripts/check_flutter_analyze_strict.sh
git diff --check

# Only after an authorized, coherent app-owned implementation.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED:
  TC-294-01 fails its composition/ownership assertions on current source.
  TC-294-02 through TC-294-05 and TC-294-10 fail on each intentionally missing
  controller symbol when their test is introduced immediately before that
  slice. TC-294-08's group mid-upload retarget assertion also fails on current
  reset behavior; that is the scoped lifecycle correction, not a baseline or
  environment failure.
- Green sentinel: both full Wired files, direct coalescer suite, migrated
  private-media/reliability locks, and the exact API contract remain green
  after every staged adapter move.
- Pre-existing dirty tree / known failure: the workspace already contains
  user-owned Wave 4A, DTR-14, scripts, tests, roadmap/index, graph, and unrelated
  code changes. Snapshot and attribute them; never revert or overwrite them.
- Environment blocker: none for host closure. No device, relay, native,
  SQLCipher, or OS callback claim is made.
- Scope drift: any public widget/model change, shared State, message/send/
  security/background-task extraction, schema/native/wire change, new
  architecture exception, fabricated group live-reaction admission change, or
  group auto-stop cleanup change blocks completion and requires a smaller
  reviewed plan.

- [x] Every controller responsibility and lane difference has a named test or
      explicit deferred owner.
- [x] TC-294-01 causal RED, per-controller RED/GREEN, and representative
      mutation re-reds are recorded in extraction order.
- [x] Direct/group exact API fingerprints, screen handoffs, composer, upload
      operation/view lifetime, voice/file ownership, reactions, Wired
      lifecycle, and coalescing sentinels pass.
- [x] Five new controller test paths are present in both 1:1 inventories and
      `GROUP_TESTS`; feature/performance discovery lists are verified.
- [x] `1to1`, `groups`, `feature-host-all`, and `performance-host` pass with
      semantic outcomes.
- [x] DTR-12 counts remain exact; runtime roots/completeness remain trustworthy.
- [x] Strict analysis has no new issue; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected and Graphify is refreshed once
      only after authorized coherent implementation.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/features/conversation/presentation/controllers/conversation_controller_composition_contract_test.dart --plain-name 'DTR-15 transfers exact owners without a shared State hierarchy'`.
- Preservation command:
  `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_change_coalesce_test.dart test/features/groups/presentation/group_conversation_wired_test.dart`.
- Manual registration: add the five
  `test/features/conversation/presentation/controllers/*_test.dart` paths to
  `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS`.
  `feature-host-all` and `performance-host` discovery are automatic.
- Migration: none.
- Boundary closure: host-only presentation ownership and deterministic
  invalidation proof; no device/relay/native/crypto/schema claim.
- Unresolved evidence: group auto-stop capture file lifetime remains a
  separately scoped cleanup finding; its current non-deletion is explicitly
  pinned and must not change under DTR-15.

## Reviewer Findings

Initial verdict: `plan-fixes-required`. The core bet was confirmed: plain
controllers composed by two unchanged private `State` roots are a viable
incremental seam. Seven verified plan fixes were applied; the final verdict is
`ready` as a planning artifact. The later `DTR15-AUTH-01` owner instruction
superseded the execution guard and authorized only this reviewed boundary.

Review grounding:

- Review query:
  `python3 graphify-arch/tdd_context.py query "Review Plan 294 DTR-15 shared direct/group conversation controller extraction: conversation_wired.dart group_conversation_wired.dart composer upload voice reaction controller ownership, no shared State, widget API preservation, rebind dispose, 1to1 groups feature-host-all performance-host counterexamples" --profile review --budget 800`.
- Result: `confidence=anchored`, `freshness=current`, fingerprint
  `c4692c00a63044ee`; both Wired files anchored. Exact lifecycle, test, and gate
  claims were verified in current source.
- A fresh read-only verifier independently returned
  `plan-fixes-required`; no reviewer edited files.

Required findings and applied deltas:

1. `TC-294-01` could accept ceremonial controllers with renamed State owners.
   It now enumerates owner types, proves exact event/screen delegation, and
   rejects duplicate/bypass listeners.
2. `TC-294-05/07` overstated group live-reaction eligibility. Current source
   filters persisted loads but not live changes, so the shared seam is narrowed
   to the pure map/reducer and lane admission remains untouched.
3. `TC-294-03/08` proved controller methods without proving the Wired lifecycle
   called them. It now separates view detach from operation-owned wake
   lifetime and adds real mid-upload retarget/unmount and late-event cases.
4. `TC-294-09` could preserve names while changing facade semantics. It now
   requires exact AST fingerprints for constructor order/types/requiredness/
   defaults, key literals, counters, `createState`, and screen handoffs.
5. `TC-294-11` relied on `--list` paths that cannot prove all three curated
   arrays. The composition contract now asserts each of the five paths exactly
   once in each array.
6. `TC-294-10` counted controller notifications and memo/Element stability,
   which could miss page `setState`. It now pumps both real Wired roots and
   counts actual rebuilds through `debugOnRebuildDirtyWidget`.
7. The deferred group auto-stop file lifetime was only prose. The strengthened
   sentinel now pins the current non-deleting/no-send/no-review outcome so this
   extraction cannot absorb the separate cleanup decision.

Five-lens close:

- L1 evidence truth: `tighten` resolved by narrowing the reaction claim.
- L2 causality: `tighten` resolved by exact ownership/API/registration
  discriminators and real Wired rebuild counting.
- L3 bypass/scope: `tighten` resolved by actual Wired rebind/dispose tests and
  immutable upload operation scope.
- L4 gate integrity: `tighten` resolved by exact three-array assertions and
  explicit per-plan, Wave 4B, and final `performance-host`.
- L5 state transitions/reversibility: `tighten` resolved by operation-versus-
  view lifetime, old/new scope tests, and the explicit no-cleanup sentinel.

Evergreen hits closed: B-2, B-3, B-4, B-5, B-6, and B-9. B-1, B-8, and B-10
are N/A because this host-only extraction changes no durable format, OS/native,
relay, crypto, device, or cross-version boundary. B-7 is clear: typed
composition remains the primary mechanism and every stop-if falls back to a
smaller lane-local seam. No unresolved plan blocker or user decision remains;
the authorized implementation is now Plan-green. Wave 4B acceptance was later
proven separately by the same-tree gate pair recorded below.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-28 CEST | Authorization / RED | Plan 294; five controller contracts; both Wired adapters | `DTR15-AUTH-01`; TC-294-01 and missing-controller REDs failed as designed | Four absent owners and the group retarget gap were causal; representative bypass mutations re-redded composition, upload, and voice fences | implement only the reviewed seams | composer, upload, voice, reaction slices |
| 2026-07-28 CEST | Incremental GREEN | four shared controllers; direct/group Wired; focused tests | focused controller/direct proof passed 151 assertions; focused group/security proof passed | Four plain `ChangeNotifier` controllers own only common presentation mechanics; both private States remain independent composition roots and public fingerprints remain exact | group send lifetime needed adversarial closure | add unmount/ABA tests |
| 2026-07-28 CEST | Async hardening | group Wired and background-task/retarget tests | success-after-unmount RED observed parent stuck `sending`; ABA mutation RED observed a stale second upload | captured `_GroupConversationSendLane`, monotonic binding generation, and separate backend/UI continuation fences make ordinary same-binding sends terminal while fencing A→B and A→B→A | no remaining focused blocker | run curated/family gates |
| 2026-07-28 CEST | Required gates | gate inventories and affected tests | `1to1`: 2,458 Flutter assertions plus relay tail; `groups`: 3,259 plus group forwarding/private-media/relay tails; `feature-host-all`: 8,438 pass / 1 declared skip across 810 paths; `performance-host`: 106 assertions across 21 paths | all four user-required gates exited 0; five controller paths occur exactly once in all three curated arrays | per-plan gate closure green | policy and hygiene |
| 2026-07-28 CEST | Policy / hygiene | architecture, roots, completeness, analyzer, diff | 1,033 sources / 182 dependency pins / 24 placement pins / 0 issues; 1,355/1,355 tests classified; strict analysis no issues; `git diff --check` clean | all new controllers are main-reachable explained roots; no exception or public facade drift | host closure green | refresh Graphify |
| 2026-07-28 CEST | Graph / close | architecture graph and TDD overlay | incremental refresh: 7 changed / 2,891 unchanged; 63,239 nodes / 95,088 edges; affected query resolved all six production files and expected roots/harnesses | graph SHA-256 `c97aa8067fb93d00f6aa4f830cb95e36208ed3ed16ba1bcf8dc889ce2118cd0e`; overlay SHA-256 `625a17138e4acff995530534c397a24ec17dd85ff7516e97838179c754d631d7` | Plan 294 is Plan-green; no per-plan full `host-all` was run by cadence | run Wave 4B aggregate `host-all`, then same-tree `performance-host`, separately |
| 2026-07-28 CEST | Wave 4B acceptance | frozen tested tree; aggregate `host-all`; same-tree `performance-host` | `host-all`: exit 0, 1,273 items, 12,825 pass / 1 skip plus eight Go tails, 1,898 s; `performance-host`: exit 0, 106/106 across 21 paths, 97 s | Both passed against `51455d3c1905a6bd70be63c59fdcc3860623778f`; retained receipt: [Wave 4B evidence](evidence/dtr-wave4b/README.md) | DTR-15 is Plan-green/Wave-accepted; no Wave 4B blocker | final release `host-all`, then `performance-host` |
