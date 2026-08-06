# 341 - Fresh-Group Bootstrap Peer-Refresh Lag

Status: implemented and acceptance-evidence complete (2026-08-06)
Type: Bug
Spec: free-text intent from 2026-08-06: speed up create-group invite startup without weakening membership convergence
Classification: implementation-complete; the reviewed quantitative closure contract was owner-approved and satisfied on 2026-08-06
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-06 12:35 CEST | Evidence Collector | `create_group_with_members_use_case.dart`, `bridge_group_helpers.dart`, `go-mknoon/bridge/bridge.go`, `go-mknoon/node/pubsub.go`, Plan 267 evidence | Confirmed that fresh creation synchronously asks not-yet-invited contacts to become topic peers; the native dial/settle branch can consume two 500 ms waits plus the outer zero-peer 150 ms settle. | Bound the smallest opt-in seam and preservation surface. |
| 2026-08-06 13:19 CEST | Planner | Dart/Go tests, groups/host gates, latency runner/harness/validator, live Android matrix | Keep the signed `members_added` event; skip only foreground peer refresh for its fresh-group bootstrap publish; retain normal refresh everywhere else. | Run independent `$tdd-review`, patch only source-backed blockers, then hand off. |
| 2026-08-06 13:34 CEST | Reviewer | `bridge.go`, `pubsub.go`, native delivery tests, invite-latency runner/validator/orchestrator, Plan 267 provenance, gate discovery | Core bet confirmed. Tightened the real bridge-entrypoint proof, zero-peer/background-discovery proof, closure failure semantics, current pre-edit baseline, shell registration, and rollback. The numeric acceptance contract remains product-owned. | Obtain explicit owner acceptance of `950/1300 ms` or replace those values and rerun the quantitative review lens. |
| 2026-08-06 13:46 CEST | Product Owner | Plan 341 quantitative closure contract | Explicitly accepted fixed-cell `phaseMedianMs.pre_fanout <= 950 ms` and `callerMedianMs <= 1300 ms`. The sole review blocker is closed without changing the reviewed values. | Execute from the current-source paired-Android baseline step. |

## Problem And Evidence

- Behavior to improve: after a creator selects friends and taps Create, the app spends about 1.4 seconds in `pre_fanout` before the first invite send begins.
- Impact: the group appears to hang during its primary creation action even though the selected contacts cannot join the new topic until they receive and accept their invites.
- Confirmed root cause/current gap: `createGroupWithMembers` updates Go with the full post-add roster and then awaits the initial signed `members_added` publish at `lib/features/groups/application/create_group_with_members_use_case.dart:295-391`. `PublishGroupMessage` always calls `ensureGroupTopicPeersBeforePublish` at `go-mknoon/node/pubsub.go:283-325`; that function calls `dialKnownGroupMembers` at `:3046-3098`. For a reachable but not-yet-subscribed selected contact, the dial path can wait 500 ms, try relay fallback, wait another 500 ms at `:2585-2593`, and then perform the outer 150 ms zero-peer settle from `go-mknoon/node/config.go:68-70`.
- Existing coverage: Plan 267's validated 30-sample Android historical reference records `create|online-cold` `pre_fanout` median/max `1443.289/1659.114 ms` versus `create|offline` `623.493/688.939 ms` at `Test-Flight-Improv/267-group-invite-send-lag-tdd-plan.md:583-601`. It is cause/provenance evidence, not Plan 341's comparison baseline: the measured pre-fanout source has changed since that run and the current emulator is API 37 rather than API 35. `TestGP007ZeroPeerPublishUsesBoundedSettleWait` proves that ordinary publishes intentionally enter the zero-peer refresh path.
- Missing coverage: no fresh-bootstrap-only bridge control exists; no test proves that the real `GroupPublish` handler consumes that control or that this one publish may bypass refresh while still authorizing, encrypting, signing, calling `topic.Publish`, and leaving background discovery alive; no current pre-edit baseline exists on the pinned Android pair; the already-defined latency `closure` mode is rejected by the runner and both harness roles and is still registered as `baseline`.
- Confirmed membership authority: each invite embeds the current full group config at `lib/features/groups/application/send_group_invite_use_case.dart:164-183,306-345`; acceptance materializes every roster member and key and joins Go with the same config at `lib/features/groups/application/handle_incoming_group_invite_use_case.dart:1006-1023,1093-1115,1174-1182`.
- Refuted findings: waiting for the initial topic publish is not what keeps a fresh invitee's roster current; the invite is the bootstrap authority. Removing `members_added` globally is also invalid because established members consume it to save additions and refresh native config at `lib/features/groups/application/group_message_listener_system_transition_processor.dart:1589-1745`. Reordering invites, deferring the whole fanout, or adding an outbox is not needed for this native preflight defect.
- Resolved finding: on 2026-08-06, the product owner explicitly accepted fixed-cell `phaseMedianMs.pre_fanout <= 950 ms` and `callerMedianMs <= 1300 ms`. No planning blocker remains. The current pre-edit paired-Android baseline is still mandatory first execution evidence, not a substitute for the approved bounds.
- Affected production files: `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/node/pubsub.go`.
- Affected test, harness, and gate files: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `go-mknoon/{bridge/bridge_test.go,node/pubsub_delivery_test.go}`, `test/integration/invite_reliability_runner_contract_test.dart`, the existing invite-latency runner/harness/support contract, and their existing groups/host/reliability registrations.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `1ae77eb3015c72a7`; stale only at `ios/Flutter/flutter_export_environment.sh`, which is generated and outside this Android-only plan.
- Query / profile: `python3 graphify-arch/tdd_context.py query "createGroupWithMembers bootstrap members_added callGroupPublish skip peer refresh invite_send_latency GROUP_TESTS" --profile tdd --budget 700`.
- Anchors: `createGroupWithMembers` -> `lib/features/groups/application/create_group_with_members_use_case.dart:119`; `callGroupPublish` -> `lib/core/bridge/bridge_group_helpers.dart:279`; `GROUP_TESTS` -> `scripts/run_test_gates.sh:410`.
- Surfaced proof/gate files: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, and `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: native Go publish/dial internals, the retained Plan 267 device artifact record, and the reliability runner's currently blocked `closure` mode were not represented in the app-owned architecture graph and were verified directly.
- Reuse rule: anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a default-off `skipPeerRefresh` control to the outer Dart `group:publish` command and set it only for the initial fresh-group `members_added` call.
- Decode that control separately in the Go bridge; map it to a typed `GroupPublishTransportOptions` value that never enters message options or encrypted `extra`.
- Preserve the current `PublishGroupMessage` signature as the default wrapper. Add an options-bearing variant that samples `len(topic.ListPeers())`, bypasses only `ensureGroupTopicPeersBeforePublish` when opted in, and still performs validation, device binding, envelope build/encrypt/sign, `topic.Publish`, and publish diagnostics.
- Enable and register the existing `invite_send_latency --mode closure` path, keeping the existing 30-sample matrix and making its host disposition mode-aware.
- Before any production, harness, or test edit, capture one valid current-source `baseline` artifact with the same USB Android, Android emulator, scenario, sample matrix, binding verification, and relay provenance used for closure. Preserve its exact `create|online-cold` `phaseMedianMs.pre_fanout` and `callerMedianMs`; Plan 267's older result remains contextual only.

Must preserve:

- Signed initial `members_added`, full post-add config, ordering before invite fanout, and soft publish-failure behavior -> TC-341-01 and existing `GL-005`/publish-failure assertions.
- Fresh invite full-roster/key convergence -> TC-341-06.
- Established-group `members_added` broadcast, native refresh, durable replay, and receiver roster update -> TC-341-02 and TC-341-07.
- Normal publish peer recovery, writer authorization, encrypted-extra shape, and zero-peer success -> TC-341-04 and TC-341-05.
- Old/new component skew -> omitted or unknown top-level JSON defaults to ordinary refresh; no existing bridge or node caller opts in implicitly.
- Background group discovery -> the bootstrap control skips only the synchronous publish preflight; the `groupDiscoveryCtx[groupId]` owner remains present and its cadence/lifecycle remain source-unchanged.

Quantitative closure contract, owner-approved on 2026-08-06:

- Baseline mode keeps its existing global dominant-cell derivation, validates as evidence, and always reports `productionAuthorized: false`.
- Closure mode pins disposition to `create|online-cold`; it reads that cell's literal `phaseMedianMs.pre_fanout` and `callerMedianMs` fields rather than whichever cell/phase is globally largest.
- Closure validation is successful only when `phaseMedianMs.pre_fanout <= 950 ms`, `callerMedianMs <= 1300 ms`, all existing exact-event checks pass, every sample has zero unknown outcomes, and `productionAuthorized == true`. Either timing miss makes summary validation non-OK and the orchestrator exit non-zero; a consistent `productionAuthorized: false` closure summary is not a passing result.
- The closure evidence records both fixed-cell medians and their deltas from the current pre-edit baseline. If the pre-edit baseline already satisfies both accepted bounds, stop before implementation and re-review Plan 341 as potentially stale rather than manufacturing a performance change.
- Authorization covers only the Plan 341 fresh-bootstrap peer-refresh optimization. It does not authorize any Plan 267 UI decoupling, outbox, delivery-semantic, add-member, or timeout change.

Hard `Do not`:

- Do not remove or background the signed `members_added` publish, send invites before it, optimistically navigate before truthful invite-attempt settlement, or add a delivery outbox.
- Do not change membership/config/invite payloads, signatures, encrypted extras, schemas, epochs, watermarks, retry identity, publish timeouts, dial waits, background discovery cadence, or ordinary/reliable/reaction publish behavior.
- Do not pass the control through Go's message `opts` map; `buildGroupMessageExtra` copies that map into the encrypted payload at `go-mknoon/node/pubsub.go:1833-1848`.
- Do not create a second latency scenario, reduce the retained matrix, add manual phone taps, run an iOS build, invoke an iOS simulator, or use an iPhone.

Deferred / accepted difference:

- Optimizing the remaining roughly 0.5-0.7 second local-create floor -> owner: a later evidence-led groups performance plan, only if the Plan 341 closure artifact shows a material residual bottleneck.
- Existing-group add latency -> intentionally unchanged; that path targets already-established members and retains foreground recovery and durable broadcast replay.

Dependencies:

- Plan 267 supplies the historical cause evidence and the existing artifact contract, not a comparable current baseline. Plan 341 supersedes only its broad H2 design direction with this reviewed narrow native seam; it does not adopt the rejected UI-decoupling/outbox design. The 2026-08-06 owner acceptance of Plan 341's exact bounds supplies the previously missing absolute create-path acceptance contract.
- Android device proof depends on a verified rebuilt Go Android binding via `./scripts/ensure_go_android_bindings.sh`; no Kotlin method or iOS framework change is required because the current wrapper forwards the JSON payload unchanged.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-341-01 | Only the fresh create flow marks its signed initial `members_added` publish as bootstrap/no-refresh. | `test/features/groups/application/create_group_with_members_use_case_test.dart::TC-341-01 fresh-group bootstrap members_added skips pre-publish peer refresh without changing the signed transition` | Host / fake bridge plus in-memory repositories | Runtime RED: outer publish payload lacks `skipPeerRefresh`; GREEN: it is `true`, while decoded signed text retains `members_added`, full selected roster/config, message ID, device binding, and publish-before-invite ordering. | Remove the create-call opt-in or helper serialization -> TC-341-01 red. | `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'TC-341-01 fresh-group bootstrap members_added skips pre-publish peer refresh without changing the signed transition'`; existing `GROUP_TESTS` entry at `scripts/run_test_gates.sh:657`, AUTO `feature-host-all`. |
| TC-341-02 | Existing-group additions keep ordinary peer refresh and signed broadcast behavior. | `test/features/groups/presentation/contact_picker_wired_test.dart::TC-341-02 existing-group members_added keeps normal peer refresh` | Host widget / fake bridge and in-memory repositories | GREEN sentinel: outer publish omits `skipPeerRefresh` and retains one signed `members_added`; GREEN remains after the fresh-only change. | Make the helper default true or opt in `ContactPickerWired` -> TC-341-02 red. | `flutter test test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'TC-341-02 existing-group members_added keeps normal peer refresh'`; existing `GROUP_TESTS` at `scripts/run_test_gates.sh:633`, AUTO `feature-host-all`. |
| TC-341-03 | The real Go bridge entrypoint consumes the top-level transport control, maps it separately, and never copies it into encrypted message options. | `go-mknoon/bridge/bridge_test.go::TestTC34103GroupPublishMapsPeerRefreshControlOutsideMessageOpts` | Host / started singleton node, joined groups with one absent configured remote member, `recordingBridgeCallback`, plus direct option-map assertions | Runtime RED: the handler has no control and always invokes the default method; GREEN: omitted/false calls through real `GroupPublish` and emits `publish_peer_refresh_begin/done`, true succeeds with `topicPeers == 0`, emits `group:publish_debug`, emits neither refresh step, and `buildGroupBridgeMessageOpts(params, false)` plus `(..., true)` both exclude the control. | Leave `GroupPublish` calling `PublishGroupMessage`, hard-code either option value, or put the control in either message-opts builder mode -> TC-341-03 red. | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestTC34103GroupPublishMapsPeerRefreshControlOutsideMessageOpts$' -count=1)`; add to the curated groups Go leg and existing `GO_BRIDGE_ENTRYPOINT_REFACTOR_RUN` host-all tail. |
| TC-341-04 | Bootstrap mode skips only foreground peer recovery, remains authorized, publishes with either live or zero topic peers, and leaves background discovery owned. | `go-mknoon/node/pubsub_delivery_test.go::{TestTC34104BootstrapPublishSkipsOnlyPeerRefreshAndStillPublishes,TestTC34104BootstrapPublishPreservesAuthorizationBeforeCrypto}` | Host / real in-process libp2p topics and Ed25519/group crypto; delivery, zero-live-peer, and discovery-lifecycle subtests | Compile RED: typed options method is absent; GREEN: the isolated live-recipient subtest receives exact ID/text with no publish-refresh event or leaked control; the zero-live-peer subtest returns success and `topicPeers == 0`, emits `group:publish_debug` but no `publish_peer_refresh_begin/done`, and retains `groupDiscoveryCtx[groupId]`; the unauthorized subtest fails before crypto/publish. | Restore unconditional refresh, return before `topic.Publish`, cancel/remove background discovery, bypass writer validation, or leak the control into extras -> a TC-341-04 subtest red. | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^(TestTC34104BootstrapPublishSkipsOnlyPeerRefreshAndStillPublishes|TestTC34104BootstrapPublishPreservesAuthorizationBeforeCrypto)$' -count=1)`; add to the curated groups Go leg and existing `GO_NODE_LIBP2P_REFACTOR_RUN` host-all tail. |
| TC-341-05 | Every default native caller retains foreground zero/partial-peer recovery and the existing envelope contract. | `go-mknoon/node/pubsub_delivery_test.go::{TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend,TestGP007ZeroPeerPublishUsesBoundedSettleWait,TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish,TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent}` | Host / real in-process libp2p and crypto | GREEN sentinel: normal calls refresh, settle, authorize, publish, and preserve extras before and after the change. | Make the wrapper opt out by default, remove refresh, move validation, or alter extras -> at least one sentinel red. | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^(TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend|TestGP007ZeroPeerPublishUsesBoundedSettleWait|TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish|TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent)$' -count=1)`; existing tests plus the new curated groups Go leg. |
| TC-341-06 | The invite remains the authoritative fresh-join roster/key carrier. | `test/features/groups/application/send_group_invite_use_case_test.dart::invite payload includes full groupConfig with members array`; `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart::persists all members from groupConfig, not just sender`; `test/features/groups/integration/invite_round_trip_test.dart::BB-007 accepted pending invite joins with exact full config and replays accepted epoch` | Host / real payload construction with in-memory repositories and fake bridge | GREEN sentinel: sender embeds all configured members; receiver persists all members/key and joins with exact config/epoch. | Truncate `effectiveGroupConfig`, persist only sender/self, or rebuild join config -> a TC-341-06 sentinel red. | `flutter test test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'invite payload includes full groupConfig with members array' && flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists all members from groupConfig, not just sender' && flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name 'BB-007 accepted pending invite joins with exact full config and replays accepted epoch'`; all three are existing `GROUP_TESTS`/AUTO `feature-host-all`. |
| TC-341-07 | Established members still apply `members_added` to durable roster, Go config, timeline, and retry path. | `test/features/groups/application/group_message_listener_test.dart::members_added saves all members and calls updateConfig`; `test/features/groups/presentation/contact_picker_wired_test.dart::G3: members_added soft publish failure durably enqueues the broadcast and keeps the members + advances the watermark` | Host / listener stream plus widget/in-memory repositories | GREEN sentinel: all members save, native config updates, timeline/watermark advances, and soft-failed broadcasts remain queued. | Skip a member save/native update or remove the signed durable enqueue -> a TC-341-07 sentinel red. | `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'members_added saves all members and calls updateConfig' && flutter test test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'G3: members_added soft publish failure durably enqueues the broadcast and keeps the members + advances the watermark'`; existing `GROUP_TESTS` at `:619/:633`, AUTO `feature-host-all`. |
| TC-341-08 | Baseline remains evidence-only; latency closure is executable and cannot pass with a slow, wrong-cell, or delivery-ambiguous result. | `test/integration/invite_reliability_runner_contract_test.dart::TC-341-08 closure mode is executable and rejects any slow or ambiguous result`; `scripts/test/reliability_simulation_discovery_contract_test.sh` | Host / synthetic 30-sample artifacts plus runner/harness source and shell discovery | Runtime RED: three source guards reject closure, disposition is globally selected/always false, and discovery prints baseline; GREEN: baseline derivation remains unchanged and false, while closure pins `create|online-cold`, reads `phaseMedianMs.pre_fanout` and `callerMedianMs`, authorizes only when both accepted bounds plus all existing exact-event/zero-unknown rules pass, and rejects a false disposition. Independent over-`950 ms` phase and over-`1300 ms` caller artifacts make validation non-OK; the registered mode is `closure`. | Re-add a closure guard, select the global largest cell, accept `productionAuthorized: false`, relax either timing/event rule, or leave registration at baseline -> host or shell test red. | `flutter test test/integration/invite_reliability_runner_contract_test.dart --plain-name 'TC-341-08 closure mode is executable and rejects any slow or ambiguous result' && bash scripts/test/reliability_simulation_discovery_contract_test.sh`; runner contract remains in `GROUP_TESTS`; the shell test is AUTO-discovered by `./scripts/run_test_gates.sh sims-contracts`. |
| TC-341-09 | A current pre-edit reference and post-change closure prove the real Create tap is faster without losing pending-invite receipt across the Flutter-to-Go/relay boundary. | `invite_send_latency --mode baseline` followed by `--mode closure` / two validated host summaries for USB Pixel 6 `21071FDF600CSC` + Android emulator `emulator-5554` | Paired device / real Flutter UI, Go Android binding, crypto, relay, target-local artifact custody; fully automated | Before edits: one 30-sample baseline validates but cannot authorize production. Device-only closure HEAD failure: runner exits 64 because closure is reserved. GREEN: both closure roles exit 0, 30/30 samples validate, the fixed-cell `phaseMedianMs.pre_fanout <= 950 ms` and `callerMedianMs <= 1300 ms`, both same-pair before/after deltas are recorded, every sample has exactly one correlated pending-invite event, and no outcome is unknown. | Re-enable bootstrap refresh, skip invite send, duplicate/drop correlation, validate a false disposition, or compare against only the historical Plan 267 run -> device run/validator/evidence review red. | Pre-edit direct runner in `baseline`, then `RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 ./scripts/run_test_gates.sh reliability-sim group --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency` after switching the one existing row to `closure`; no manual taps and no iOS. |

### Test Notes

- TC-341-03: use separate joined groups/subtests for omitted and true control, each configured with self plus one absent remote member so the default path must enter refresh. Cancel periodic discovery only to isolate the bridge-handler event assertion; assert control absence from both option-builder recipient modes, while the node-level lifecycle proof belongs to TC-341-04.
- TC-341-04: cancel the sender's periodic discovery loop only in the live-delivery isolation subtest. In the zero-live-peer subtest, do not cancel it; assert the discovery context remains registered after publish and discriminate specifically on the two `publish_peer_refresh_*` steps so unrelated background-discovery events cannot satisfy or fail the assertion.
- TC-341-08/09: preserve the existing create/add x online-warm/online-cold/offline x five-repetition matrix. Only fresh create receives a performance ceiling; add remains in the matrix as the unchanged default-path discriminator.
- TC-341-09 proves exact pending-invite receipt, not acceptance. TC-341-06 owns deterministic accepted-roster/key convergence; no phone acceptance journey is added.
- TC-341-09: the retained Plan 267 medians were `1443.289 ms` pre-fanout and `1796.962 ms` caller settlement. The owner-approved round `950/1300 ms` bounds target roughly a 0.5 second material improvement without pretending to be a universal SLA.

## Implementation Steps

1. Snapshot `git status --short`; record every unrelated dirty path. Verify the current Android Go binding, rediscover only the pinned USB Android and Android emulator, and run the existing 30-sample scenario once in `baseline` mode before any production, harness, or test edit. Preserve both role artifacts, capture receipt, host summary, source/native/relay provenance, hashes, and the fixed-cell medians. Stop-if: either target is unavailable, artifact validation fails, provenance is unstable, or the current baseline already meets both accepted bounds; the last case requires stale-plan re-review rather than implementation.
2. Add TC-341-01, the real-handler TC-341-03, the three-path TC-341-04, and TC-341-08 before production edits and capture their documented RED reasons. Run the existing GREEN sentinels before changing shared code.
3. Add default-off `skipPeerRefresh` serialization in `callGroupPublish`; pass `true` only at the fresh-create initial `members_added` call. Stop-if: any other Dart production caller needs modification or the signed `text` changes.
4. Decode the top-level control in `groupBridgeMessageParams`, map it to `GroupPublishTransportOptions`, make the production `GroupPublish` handler call the options-bearing node method, preserve `PublishGroupMessage` as a zero/default wrapper, and bypass only `ensureGroupTopicPeersBeforePublish` inside the options-bearing implementation. Stop-if: the control enters message opts, validation/envelope build moves, `topic.Publish` becomes conditional, or background discovery ownership/cadence changes.
5. Remove only the runner and two role guards that reserve closure. Keep baseline derivation valid and non-authorizing; make closure derive from the fixed `create|online-cold` fields and make summary validation/orchestration fail unless both accepted bounds, `productionAuthorized == true`, and every existing delivery/custody/correlation rule pass. Retain the artifact shape, sample matrix, and custody checks.
6. Register TC-341-03/04 in one small groups Go leg used by `groups` and `all`; append their patterns to the existing node/bridge host-all synthetic invocations. Switch only the existing invite-latency reliability row to `closure` and update its AUTO `sims-contracts` discovery contract. Do not add a new runner, scenario, Go tail, or device row.
7. Run focused GREEN, representative mutation re-reds, exact preservation sentinels, the complete curated `groups` gate, runner/discovery contracts, analyzer, and diff hygiene.
8. Rebuild/verify the Android Go binding, confirm the same two Android targets and relay provenance, list the registered closure command, and run TC-341-09 once. Record the second artifact set, the literal fixed-cell fields, and their deltas from the current pre-edit baseline. A closure summary that is valid-but-non-authorizing is a failure, not a successful run.

## Risks And Blind Spots

- A transport flag could leak into signed/encrypted content -> TC-341-01, TC-341-03, and the received-extra assertion in TC-341-04.
- An early skip could accidentally bypass authorization, crypto, or actual publish -> both TC-341-04 tests plus TC-341-05.
- A default change could weaken established-group delivery -> TC-341-02, TC-341-05, TC-341-07, and the add cells in TC-341-09.
- Mixed Dart/native versions could disagree on the new field -> JSON omission defaults false; an older native ignores the unknown top-level key and remains slower, while a newer native with old Dart retains normal refresh.
- Rollback is immediate and state-free: remove the single fresh-create opt-in (or force its default false) and the preserved wrapper restores ordinary refresh. No stored or wire state needs migration, cleanup, replay, or downgrade handling.
- Lifecycle / derived-state durability: TC-341-06 proves accepted invite material is durably reconstructed into group/member/key state; TC-341-07 proves established transitions remain durable.
- Sibling-surface consistency: TC-341-02 and the default wrapper in TC-341-05 keep all other `callGroupPublish`, reliable-send, reaction, and existing-add paths unchanged.
- Destructive-action side effects: N/A — no deletion, cleanup, cancellation, migration, or file lifecycle changes.
- Invariant re-verification under new transitions: the existing independent background discovery loop remains source-unchanged and TC-341-04 proves its group-owned context survives the new bootstrap path; no reset/re-entry transition is added.

## Gate Cadence

- Per-plan closure after the owner gate: one paired-Android pre-edit baseline, focused TC-341 causal tests, exact TC-341 preservation sentinels, `flutter test test/core/bridge/bridge_group_helpers_test.dart`, the new exact Go node/bridge legs, `./scripts/run_test_gates.sh groups`, the exact AUTO-discovered reliability shell contract, Android binding verification, and one paired-Android closure run. The curated groups gate already includes all affected feature tests, so neither `feature-host-all` nor `core-host-all` is duplicated here.
- Do not run full `host-all` for this individual plan. Run `./scripts/run_host_test_gates.sh host-all` once after the next Groups Reliability dependency wave containing Plan 341, and once at final rollout/release closure. TC-341-03/04 must first be added to the existing synthetic Go host-all patterns so those later runs actually select them.
- Shared tests outside feature/core globs: run `bash scripts/test/reliability_simulation_discovery_contract_test.sh` and both exact Go commands directly; aggregate registration is AUTO `sims-contracts` for the shell test and the reused host-all Go tails for native tests.

## Acceptance Gates

Execution prerequisite satisfied on 2026-08-06: the product owner accepted fixed-cell `phaseMedianMs.pre_fanout <= 950 ms` and `callerMedianMs <= 1300 ms`. The commands below are now the execution contract, beginning with the pre-edit baseline.

```bash
# Snapshot before execution; preserve unrelated changes.
git status --short

# Current-source pre-edit baseline. Run before any test, harness, or production edit;
# preserve the validated artifacts/provenance and do not substitute an iOS target.
./scripts/ensure_go_android_bindings.sh
flutter devices --machine
adb devices -l
dart run integration_test/scripts/run_invite_reliability_multi_device.dart \
  --scenario invite_send_latency --mode baseline \
  -d 21071FDF600CSC,emulator-5554

# First causal RED; expect non-zero because the fresh publish lacks the opt-in.
flutter test test/features/groups/application/create_group_with_members_use_case_test.dart \
  --plain-name 'TC-341-01 fresh-group bootstrap members_added skips pre-publish peer refresh without changing the signed transition'

# Native causal RED; expect non-zero because the typed options API is absent.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestTC34104BootstrapPublishSkipsOnlyPeerRefreshAndStillPublishes|TestTC34104BootstrapPublishPreservesAuthorizationBeforeCrypto)$' \
  -count=1)

# Focused Dart GREEN; expect exit 0 and both fresh/default route tests selected.
flutter test \
  test/features/groups/application/create_group_with_members_use_case_test.dart \
  test/features/groups/presentation/contact_picker_wired_test.dart

# Focused native GREEN and transport-control isolation; expect exit 0.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestTC34104BootstrapPublishSkipsOnlyPeerRefreshAndStillPublishes|TestTC34104BootstrapPublishPreservesAuthorizationBeforeCrypto)$' \
  -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^TestTC34103GroupPublishMapsPeerRefreshControlOutsideMessageOpts$' \
  -count=1)

# Exact default-path and roster preservation; expect exit 0 and target tests selected.
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend|TestGP007ZeroPeerPublishUsesBoundedSettleWait|TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish|TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent)$' \
  -count=1)
flutter test test/features/groups/application/send_group_invite_use_case_test.dart \
  --plain-name 'invite payload includes full groupConfig with members array'
flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart \
  --plain-name 'persists all members from groupConfig, not just sender'
flutter test test/features/groups/integration/invite_round_trip_test.dart \
  --plain-name 'BB-007 accepted pending invite joins with exact full config and replays accepted epoch'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'members_added saves all members and calls updateConfig'
flutter test test/core/bridge/bridge_group_helpers_test.dart

# Closure contract and registration; expect exit 0 and the list to print --mode closure with both IDs.
flutter test test/integration/invite_reliability_runner_contract_test.dart \
  --plain-name 'TC-341-08 closure mode is executable and rejects any slow or ambiguous result'
bash scripts/test/reliability_simulation_discovery_contract_test.sh
RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency

# Affected curated lane; expect exit 0, zero failed Flutter tests, and the registered Go legs selected.
./scripts/run_test_gates.sh groups

# Android native boundary; expect digest/rebuild verification exit 0.
./scripts/ensure_go_android_bindings.sh

# Availability-bounded Android closure; compare its fixed-cell medians with the
# preserved current-source baseline. Both exact IDs must be listed. Do not substitute iOS.
flutter devices --machine
adb devices -l
RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency

# Hygiene; expect no new analyzer issues and no whitespace errors.
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: paired-device.
- Boundary being proven: the real Create UI -> Dart use case -> Android Go bridge -> native topic/relay state -> invite receiver path, including user-visible pre-fanout/caller timing and exact recipient-event correlation.
- Live availability check: `flutter devices --machine` plus `adb devices -l` -> USB Pixel 6 `21071FDF600CSC` (Android 16/API 36) and Android emulator `emulator-5554` (Android 17/API 37) were both live on 2026-08-06.
- Required setup: verified Android Go binding, real configured relay, primary `21071FDF600CSC`, sibling `emulator-5554`, scenario `invite_send_latency`, mode `closure`, target-local Android cache exchange through the existing host broker, and no manual interaction.
- Comparison setup: before edits, run the same scenario/matrix on the same two targets in `baseline` mode and preserve its validated artifacts and app/native/relay provenance. After edits, rebuild the binding and run exactly one `closure`; Plan 267's API-35 artifact is not the comparison leg.
- Two-peer default: one pinned USB physical Android plus one pinned Android emulator with fully automated setup/actions/assertions. iOS is explicitly excluded by the user and is not needed for this non-iOS-specific boundary.
- Closure role: required closure evidence after owner threshold acceptance while both Android targets remain available; if a pinned target is unavailable at execution, record `N/A (target unavailable by project policy)` and do not replace it with iOS.
- `FLUTTER_DEVICE_ID`: host selector only; both explicit IDs remain required through `RELIABILITY_MULTI_DEVICE_IDS`.
- Registration: existing group reliability orchestrator scenario `integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency`, changed from `baseline` to `closure` after TC-341-08.
- Baseline command: `dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode baseline -d 21071FDF600CSC,emulator-5554` before any edit; require both roles and host validation to exit 0, then preserve the fixed-cell fields and provenance.
- Discovery command: `RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 ./scripts/run_test_gates.sh reliability-sim group --list --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency` -> exactly one command with `--mode 'closure' -d '21071FDF600CSC,emulator-5554'`.
- Closure command: `RELIABILITY_MULTI_DEVICE_IDS=21071FDF600CSC,emulator-5554 ./scripts/run_test_gates.sh reliability-sim group --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency` -> both roles exit 0; host validator accepts immutable role artifacts/capture receipt/summary, `productionAuthorized == true`, and the fixed timing/delivery contract. A slow but internally consistent non-authorizing summary must exit non-zero.
- Artifacts: separate baseline and closure runner-logged host directories, each containing `primary.log`, `sibling.log`, both `md004_<runId>_invite_send_latency_<role>.json` files, the host-capture receipt, and the validated host summary with stable app/native/relay provenance and SHA-256 digests; the closure record includes the literal before/after fixed-cell medians and deltas.
- Deferred device work: none. A separate invite-accept UI journey is not added because TC-341-06 proves exact accepted roster/key material at the narrower deterministic boundary.

## Execution Interpretation And Done Criteria

- Expected RED: TC-341-01 lacks the fresh outer control; TC-341-03/04 lack the bridge/node typed options seam; TC-341-08 finds blocked/unregistered closure semantics.
- Green sentinel: TC-341-02 and TC-341-05-07 keep all ordinary publish and roster-convergence behavior unchanged.
- Pre-existing dirty tree / known failure: the planning snapshot contains unrelated user changes in Plans 337-340, FDC artifacts/scripts, Graphify outputs, conversation code/tests, `info.plist`, and other files. Execution must preserve them and distinguish them from Plan 341 edits.
- Plan blocker: none. The owner-approved `950/1300 ms` fixed-cell median contract was satisfied by closure run `1786020246939` on 2026-08-06.
- Environment blocker: none at planning time. If either pinned Android target disappears during authorized execution, record the device row `N/A (target unavailable by project policy)` rather than failure or iOS substitution.
- Scope drift: any need for a DB/wire/config schema change, timeout retuning, invite reordering/outbox, reliable-send change, Kotlin API, iOS build, second scenario, or manual phone flow blocks completion and requires replan.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Harness registration is implemented and verified.
- [x] Android binding and paired-device/relay proof pass when the two policy-approved targets are available.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- Authorization: approved on 2026-08-06 for `phaseMedianMs.pre_fanout <= 950 ms` and `callerMedianMs <= 1300 ms` exactly.
- First evidence command: verify the current Android binding and capture the one pre-edit `baseline` run on `21071FDF600CSC,emulator-5554`; preserve both artifacts, receipt, host summary, provenance, hashes, and fixed-cell medians.
- First causal RED command: `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'TC-341-01 fresh-group bootstrap members_added skips pre-publish peer refresh without changing the signed transition'`.
- Preservation command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^(TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend|TestGP007ZeroPeerPublishUsesBoundedSettleWait|TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish|TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent)$' -count=1)`.
- Manual registration: add TC-341-03/04 to one curated groups Go leg and reuse the two existing host-all Go patterns; switch the existing invite-latency reliability row/discovery expectation from `baseline` to `closure`.
- Migration: none; no DB, signed/encrypted wire, config, or application schema change.
- Rollback: remove the single fresh-create `skipPeerRefresh: true` call-site value (or force the outer field false); the default wrapper restores the old synchronous refresh with no stored-state cleanup.
- Boundary closure: one fully automated USB Android + Android emulator run, pinned to `21071FDF600CSC,emulator-5554`; no iOS.
- Unresolved planning evidence: none. The current-source baseline and same-pair closure artifacts are recorded below.

## Reviewer Findings

Initial review verdict: **not-ready**. Initial plan classification: `evidence-gated`; core bet: **confirmed**. Initial disposition: **replan** — quantitative acceptance contract only; the bounded implementation design and test topology otherwise stood.

Resolved owner decision:

1. **[resolved 2026-08-06] Quantitative closure contract approved.** The product owner accepted fixed-cell `phaseMedianMs.pre_fanout <= 950 ms` plus `callerMedianMs <= 1300 ms`, with all existing exact-event and zero-unknown rules. Because the accepted values are unchanged from the reviewed proposal, no quantitative redesign or repeat counterexample pass is required.

Final verdict after owner resolution: **ready**. Plan classification: `implementation-ready`; core bet: **confirmed**. Disposition: **execute**.

Source-backed plan fixes applied during review:

- TC-341-03 now exercises the real `GroupPublish` handler, so leaving production on the default wrapper or hard-coding the option cannot pass.
- TC-341-04 now covers live delivery, zero live peers, authorization, and survival of the independent background-discovery owner.
- TC-341-08 now pins closure to `create|online-cold`, names the literal median fields, independently rejects each over-bound artifact, and makes a non-authorizing closure fail validation/orchestration. Baseline remains valid and non-authorizing.
- TC-341-09 now captures one comparable current pre-edit baseline on the same Android pair and describes the device result as pending-invite receipt, while host TC-341-06 owns acceptance/roster convergence.
- The shell contract is correctly registered through AUTO `sims-contracts`, and rollback is the state-free removal of one fresh-create opt-in.

Five-lens result after owner resolution: L1 evidence/classification, L2 causality, L3 bypass/scope, L4 gate integrity, and L5 boundary/reversibility are all `clear`. Blind-spot hits B-3 and B-4 were corrected in place; B-2, B-7, B-8, B-9, and B-10 are clear, while B-1, B-5, and B-6 are N/A for this state-free default-off transport control.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-06 13:46 CEST | not started | plan only | owner accepted `950/1300 ms` contract | reviewed plan is execution-ready | none | capture current-source paired-Android baseline before any implementation edit |
| 2026-08-06 14:17 CEST | prerequisite repair | `group_multi_device_real_harness.dart`, shared-path source contract | direct Pixel diagnostic reached SQLCipher open, identity/ML-KEM generation, node start, and relay online | invalid pre-baseline attempts were traced to `MISSING_PLUGIN` because the MD-004 harness had not acquired the canonical Android runtime owner; role-bound lease wiring fixed it | none | run the unchanged Plan 341 baseline |
| 2026-08-06 14:22 CEST | current-source baseline | run `1786018690022` | pinned Pixel 6 + `emulator-5554`; 30/30; role exits 0/0; host validator GREEN | fixed `create|online-cold`: `pre_fanout=1523.073 ms`, caller `1890.159 ms`; exact recipient events 5/5; `productionAuthorized=false` | both accepted bounds were missed, so the stop/go condition authorized implementation | add causal tests and the fresh-only transport seam |
| 2026-08-06 14:40 CEST | implementation and host closure | Dart/Go publish seam, closure contract, harness registration, tests, groups/host patterns | focused TC-341 tests and preservation sentinels GREEN; `groups` 4,054 Flutter GREEN plus four Go invocations and relay toolchain GREEN; analyzer/diff clean | default wrapper and existing-add refresh preserved; the fresh create call is the sole production opt-in; closure is registered on the exact Android pair | none | rebuild binding and run the single paired closure |
| 2026-08-06 14:48 CEST | paired-device closure | run `1786020246939` | rebuilt binding; pinned Pixel 6 + `emulator-5554`; 30/30; role exits 0/0; host validator and reliability gate GREEN | fixed `create|online-cold`: `pre_fanout=375.439 ms`, caller `1083.137 ms`; exact delivery evidence true; `productionAuthorized=true` | both owner-approved bounds passed; Plan 341 is complete | retain artifacts/hashes and include TC-341 in later wave-level `host-all` |

## Execution Evidence (2026-08-06)

### Bootstrap blocker repair

- Two inadmissible pre-baseline attempts stopped before identity artifact creation. Synchronous fatal diagnostics identified `MISSING_PLUGIN` for `generateIdentity` and `mlKemKeygen` on `com.mknoon/go_bridge`; SQLCipher migrations themselves passed a direct physical-Pixel proof.
- Root cause: the MD-004 harness reached Go bridge calls without the canonical Android runtime owner that constructs `GoBridge`. The harness now acquires and releases a role-bound `CanonicalRuntimeDeviceTestLease`; its source contract and a fresh-device diagnostic passed. No DB migration or bridge registry was changed.

### Comparable baseline and closure

Both runs used physical Pixel 6 `21071FDF600CSC` (API 36), Android emulator `emulator-5554` (API 37), the same two production relay addresses, the unchanged 30-sample create/add x warm/cold/offline matrix, and fully automated target-local custody.

| Fixed `create|online-cold` metric | Baseline `1786018690022` | Closure `1786020246939` | Delta | Result |
|---|---:|---:|---:|---|
| `phaseMedianMs.pre_fanout` | `1523.073 ms` | `375.439 ms` | `-1147.634 ms` (`-75.35%`) | PASS (`<= 950 ms`) |
| `callerMedianMs` | `1890.159 ms` | `1083.137 ms` | `-807.022 ms` (`-42.70%`) | PASS (`<= 1300 ms`) |

- Closure fixed cell: five samples, five exact recipient observations, event median/max `1/1`, zero unknown/not-observed/late outcomes, and `productionAuthorized=true`.
- Existing-add discriminator remained on ordinary refresh: `add|online-cold` pre-fanout changed only from `1445.407 ms` to `1413.992 ms`, while TC-341-02/04/05/07 remained green.
- Baseline provenance: app/native revision `366885c71677001168ccd733e6d14db251db8c0e`, dirty source fingerprint `9b3b2eb47a53c18d2f94310b87816bebf7cc87908f4138e152e509a5f1113035`, relay digest `5579561a02742fddb8f0d371f4164b04d8010a454961f7f2d2ebb4bae99613a4`.
- Closure provenance: the same app/native revision and relay digest, with post-change source fingerprint `1db9a7ca6982b5869b6c2567d8b586dc73109e31ba2af7da60f8f0b7f7a7cd4b`.

Baseline artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/invite_reliability_multi_device_VM7cHS`:

| Evidence | SHA-256 |
|---|---|
| `md004_1786018690022_invite_send_latency_primary.json` | `aad2b815307427064b2b4f3aa29d7238701baaf80ddd18517f008e018c51f46f` |
| `md004_1786018690022_invite_send_latency_sibling.json` | `090c1cc066965a75c59fd150cb876503a47aa6ee6863d995e7afb04d20e32cc9` |
| `md004_1786018690022_invite_send_latency_host_capture_receipt.json` | `26b0d5e5de6828e4ed268996438605df5d79c85884f4ee49b074760ccf231634` |
| `md004_1786018690022_invite_send_latency_host_summary.json` | `9450cafbc83c5f8dd11d1795930d1b77568612045cb71e11d90a6a472f4726d9` |

Closure artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/invite_reliability_multi_device_DkiiTC`:

| Evidence | SHA-256 |
|---|---|
| `md004_1786020246939_invite_send_latency_primary.json` | `5018bdf171d9212ae0c12266a21991c18f763276c40298c9d678337f358afae6` |
| `md004_1786020246939_invite_send_latency_sibling.json` | `9595060a8c614270ee1ce839e34c4425ad48ccb8fc4f0a25c5761af527e54efc` |
| `md004_1786020246939_invite_send_latency_host_capture_receipt.json` | `04b5e16df677e6a35e7974477c791e71ab764375d4bc37737b72276a046e2fdd` |
| `md004_1786020246939_invite_send_latency_host_summary.json` | `54408e00bd874184b3b1144d2c1ff6c65d8165071b3eb1f5940cc5ab1ae6eb17` |

### Test and gate record

- TC-341-01/02/03/04/08 and all exact TC-341-05/06/07 preservation sentinels passed. The complete bridge-helper suite passed 80 tests; the full invite reliability contract passed 14 tests.
- Representative mutation: forcing the fresh-create call-site opt-in false made TC-341-01 red with `Expected: true, Actual: <null>`; restoring the opt-in returned it green.
- `bash scripts/test/reliability_simulation_discovery_contract_test.sh` passed and the filtered reliability list printed exactly one `--mode 'closure' -d '21071FDF600CSC,emulator-5554'` command.
- `./scripts/run_test_gates.sh groups` passed: 4,054 Flutter tests, four successful Go invocations across bridge/node/relay, and the relay Go toolchain contract.
- Android binding input digest `ea7dd54d66f78fa4162ec4100ac1dae157d5913b9e9a057e5b3e31d7613437a0` rebuilt to `GoMknoon.aar` SHA-256 `fe15b060d610b01a7bc9d0b12fd5f074558aa12e767e762df764a3fd89104087`.
- Full `flutter analyze` / `flutter analyze --no-pub` reported no issues; final `git diff --check` passed. Per the project cadence, full `host-all` was not run for this individual plan; the new native tests are registered in its existing node/bridge patterns for the next dependency-wave run.
- Final Graphify incremental refresh completed with 67,767 nodes, 100,108 edges, 14,958 named tests, and 1,166 production targets.
